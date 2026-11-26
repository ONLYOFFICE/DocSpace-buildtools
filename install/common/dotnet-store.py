#!/usr/bin/env python3
# Keeps the NuGet package files that several published .NET services share once, in a package-cache layout store, instead of in every service folder.
# The services find them through additionalProbingPaths in their runtimeconfig.json; the host probes <store>/<package path>/<asset path>.
import argparse
import hashlib
import json
import os
import shutil
import sys


def file_hash(path):
    digest = hashlib.sha256()
    with open(path, "rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_assets(target_entry, rids):
    # (asset path inside the package, path of the published copy relative to the service folder)
    for group in ("runtime", "native"):
        for asset, info in target_entry.get(group, {}).items():
            yield asset, info.get("localPath") or os.path.basename(asset)
    for asset, info in target_entry.get("resources", {}).items():
        yield asset, info.get("localPath") or os.path.join(info.get("locale", ""), os.path.basename(asset))
    for asset, info in target_entry.get("runtimeTargets", {}).items():
        if info.get("rid") in rids:
            yield asset, info.get("localPath") or asset


def read_service(service_dir, rids):
    deps_files = [name for name in os.listdir(service_dir) if name.endswith(".deps.json")
                  and os.path.isfile(os.path.join(service_dir, name[:-len(".deps.json")] + ".runtimeconfig.json"))]
    packages = {}
    for deps_name in deps_files:
        with open(os.path.join(service_dir, deps_name), encoding="utf-8-sig") as stream:
            deps = json.load(stream)
        target = deps["targets"][deps["runtimeTarget"]["name"]]
        for key, library in deps.get("libraries", {}).items():
            if library.get("type") == "package" and key in target:
                files = sorted(set(package_assets(target[key], rids)))
                if files:
                    packages[key] = (library.get("path") or key.lower(), files)
    return deps_files, packages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--store", required=True, help="folder that receives the shared package files")
    parser.add_argument("--probing-path", required=True, help="path of the store as the installed services see it")
    parser.add_argument("--min-services", type=int, default=2)
    parser.add_argument("--rids", default="unix,linux,linux-x64,linux-arm64", help="runtime-specific assets of these RIDs are used")
    parser.add_argument("services", nargs="+", help="published service folders")
    args = parser.parse_args()
    rids = set(filter(None, args.rids.split(",")))

    services = {}
    absent = []
    for service_dir in args.services:
        deps_files, packages = read_service(service_dir, rids)
        if not deps_files:
            sys.exit(f"{service_dir}: no deps.json with a runtimeconfig.json")
        services[service_dir] = packages
        # With a probing path the host checks that every asset exists, so an asset missing already now would stop the service
        absent += [f"{service_dir}: {local}" for _, files in packages.values() for _, local in files
                   if not os.path.isfile(os.path.join(service_dir, local))]
    if absent:
        sys.exit("Package files listed in deps.json are missing from the publish output:\n" + "\n".join(absent[:20]))

    usage = {}
    for packages in services.values():
        for key in packages:
            usage[key] = usage.get(key, 0) + 1
    shared = {key for key, count in usage.items() if count >= args.min_services}

    stored_files = stored_bytes = removed_files = removed_bytes = kept_files = 0
    for service_dir, packages in services.items():
        for key in sorted(shared & packages.keys()):
            package_path, files = packages[key]
            for asset, local in files:
                source = os.path.join(service_dir, local)
                target = os.path.join(args.store, package_path, asset)
                if not os.path.exists(target):
                    os.makedirs(os.path.dirname(target), exist_ok=True)
                    shutil.copy2(source, target)
                    stored_files += 1
                    stored_bytes += os.path.getsize(source)
                elif file_hash(source) != file_hash(target):
                    # The host takes an app-local file first, so a different copy just stays where it is
                    kept_files += 1
                    continue
                removed_files += 1
                removed_bytes += os.path.getsize(source)
                os.remove(source)
        for root, _, _ in sorted(os.walk(service_dir), key=lambda entry: -len(entry[0])):
            if root != service_dir and not os.listdir(root):
                os.rmdir(root)

    configs = 0
    for service_dir in services:
        for name in os.listdir(service_dir):
            if name.endswith(".runtimeconfig.json"):
                path = os.path.join(service_dir, name)
                with open(path, encoding="utf-8-sig") as stream:
                    config = json.load(stream)
                config.setdefault("runtimeOptions", {})["additionalProbingPaths"] = [args.probing_path]
                with open(path, "w", encoding="utf-8") as stream:
                    json.dump(config, stream, indent=2)
                    stream.write("\n")
                configs += 1

    # Every package asset a service lists must now be either in its folder or in the store
    missing = [f"{service_dir}: {package_path}/{asset}" for service_dir, packages in services.items()
               for package_path, files in packages.values() for asset, local in files
               if not os.path.isfile(os.path.join(service_dir, local)) and not os.path.isfile(os.path.join(args.store, package_path, asset))]
    if missing:
        sys.exit("Package files missing after the move:\n" + "\n".join(missing[:20]))

    print(f"Package store: {len(shared)} of {len(usage)} packages shared by {args.min_services}+ of {len(services)} services, "
          f"{stored_files} files ({stored_bytes >> 20} MB) kept once, {removed_files} copies ({removed_bytes >> 20} MB) removed from the services, "
          f"{kept_files} differing copies left in place, probing path set in {configs} runtimeconfig.json files")


if __name__ == "__main__":
    main()
