# ONLYOFFICE DocSpace - Docker

Docker Compose definitions, image-build files and runtime configuration for
running **ONLYOFFICE DocSpace** in containers.

## Contents

- [Prerequisites](#prerequisites)
- [Directory layout](#directory-layout)
- [Quick start](#quick-start)
- [Configuration](#configuration)
- [Running with Docker Compose](#running-with-docker-compose)
- [Building images](#building-images)

## Prerequisites

- Docker Engine 24+
- Docker Compose 2.18.0+
- Docker Buildx (bundled with recent Docker) - required only to **build** images

## Directory layout

Production service files live at the root. Everything needed only to **build**
images or to run a **local development** environment lives under `build/`.

```text
install/docker/
├── *.yml                     # Production Compose files (shipped in OCI tarballs)
├── .env                      # All runtime variables (images, ports, secrets, hosts)
├── config/                   # Configs mounted into containers (nginx, mysql.cnf, fluent-bit, …)
├── build/                    # Build + local-dev assets - NOT shipped to end users
│   ├── Dockerfile            #   main multi-stage image (used by CI)
│   ├── Dockerfile.runtime    #   base runtime images (dotnet / node / router)
│   ├── Dockerfile.ffvideo    #   ffmpeg helper image
│   ├── build.hcl             #   buildx bake definition (multi-arch)
│   ├── build.yml             #   compose build definition
│   ├── entrypoints/          #   scripts COPY'd into images at build time
│   │   ├── docker-entrypoint.py
│   │   ├── docker-identity-entrypoint.sh
│   │   ├── docker-migration-entrypoint.sh
│   │   ├── docker-healthchecks-entrypoint.sh
│   │   ├── bin-share-docker-entrypoint.sh / wait-bin-share-docker-entrypoint.sh
│   │   └── prepare-nginx-router.sh
│   ├── dev/                  #   local-dev-only Compose overlays (build.backend.docker.py)
│   │   ├── db.dev.yml            #   MySQL dev overrides (exposed ports)
│   │   ├── docspace.profiles.yml #   local-dev application stack
│   │   ├── docspace.overcome.yml #   local-dev overrides
│   │   ├── dnsmasq.yml           #   local DNS for development
│   │   └── build-identity.yml    #   ASC.Identity (Java) build
│   └── stack/supervisor/     #   supervisor configs baked into the image
└── community/                # single-container community edition stack
```

### Production Compose files

| File | Service |
|------|---------|
| `docspace.yml` | All DocSpace application services (modular) |
| `docspace-stack.yml` | Same application services bundled as one stack |
| `db.yml` | MySQL |
| `ds.yml` | ONLYOFFICE Document Server |
| `redis.yml` · `rabbitmq.yml` | Redis · RabbitMQ |
| `opensearch.yml` · `dashboards.yml` · `fluent.yml` | OpenSearch + Dashboards + Fluent Bit |
| `identity.yml` | OAuth2 identity service |
| `notify.yml` | Notification service |
| `healthchecks.yml` | Health-check UI |
| `migration-runner.yml` | One-shot DB migration container |
| `proxy.yml` · `proxy-ssl.yml` | Nginx reverse proxy (HTTP · HTTPS) |

## Quick start

The one-click installer pulls the published images, generates `.env` and starts
the whole stack - the recommended path for most users:

```bash
# from the repository root
bash install/OneClickInstall/install-Docker.sh

# stack mode (single bundled application container)
bash install/OneClickInstall/install-Docker.sh -sm true
```

> [!TIP]
> Prefer the installer for production. The manual Compose commands below are for
> custom setups and for understanding how the pieces fit together.

## Community edition

A lightweight, single-container DocSpace solution you bring up with a single
`docker compose` command — no extra infrastructure to wire up. See
[`community/`](community/README.md).

## Configuration

All settings come from [`.env`](.env) (~200 variables: image versions, ports,
hosts, credentials). Compose reads it automatically when you run from this
directory.

Review these before the first start:

| Variable | Purpose |
|----------|---------|
| `APP_CORE_MACHINEKEY` | Internal services shared secret |
| `DOCUMENT_SERVER_JWT_SECRET` | Document Server JWT secret |
| `DOCUMENT_SERVER_JWT_HEADER` | Document Server JWT header name |
| `EXTERNAL_PORT` · `EXTERNAL_PORT_HTTPS` | Published HTTP / HTTPS ports |
| `REGISTRY` · `DOCKER_TAG` | Image registry prefix and tag |

> [!IMPORTANT]
> Change `APP_CORE_MACHINEKEY` and `DOCUMENT_SERVER_JWT_SECRET` from their
> defaults before exposing the instance to a network.

## Running with Docker Compose

Compose is **modular** - files are combined with `-f`. Run all commands from
`install/docker/` so that `.env` is picked up.

**Modular** (individual application services):

```bash
docker compose \
  -f docspace.yml -f healthchecks.yml -f identity.yml -f notify.yml \
  -f dashboards.yml -f db.yml -f ds.yml -f fluent.yml -f opensearch.yml \
  -f proxy.yml -f rabbitmq.yml -f redis.yml \
  up -d
```

**Stack** (application bundled in one container + dependencies):

```bash
docker compose \
  -f docspace-stack.yml -f dashboards.yml -f db.yml -f ds.yml -f fluent.yml \
  -f opensearch.yml -f proxy.yml -f rabbitmq.yml -f redis.yml \
  up -d
```

### HTTPS / SSL

Once the stack is running, enable HTTPS with the
[`config/docspace-ssl-setup`](config/docspace-ssl-setup) helper. It switches the
proxy to `proxy-ssl.yml`, installs the certificate and sets up automatic
renewal - run it from `install/docker/`:

```bash
# Let's Encrypt (auto-renew); EMAIL and DOMAIN(s), comma-separated
config/docspace-ssl-setup support@example.com example.com,s1.example.com

# bring your own certificate (PEM/PFX/DER/CER; key required unless PFX)
config/docspace-ssl-setup --file example.com /etc/ssl/example.crt /etc/ssl/example.key

# revert to the default (HTTP) proxy configuration
config/docspace-ssl-setup --default
```

> [!NOTE]
> The script must run next to `.env`, `proxy.yml` and `proxy-ssl.yml` (i.e. from
> `install/docker/`). Run `config/docspace-ssl-setup` without arguments for full
> usage, including wildcard-domain (DNS-01) certificates.

> [!TIP]
> To avoid repeating long `-f` chains, export the file list once:
> ```bash
> export COMPOSE_FILE=docspace.yml:healthchecks.yml:identity.yml:notify.yml:dashboards.yml:db.yml:ds.yml:fluent.yml:opensearch.yml:proxy.yml:rabbitmq.yml:redis.yml
> docker compose up -d        # then just use plain compose commands
> ```

## Building images

Images are built with **buildx bake** from the `build/` definition. The build
clones the source repositories (buildtools / server / client) by branch inside
the image, so a local source checkout is **not** required.

Run from `install/docker/` so the adjacent `.env` is picked up:

```bash
cd install/docker

# all services
docker buildx bake -f build/build.hcl

# a single group
docker buildx bake -f build/build.hcl dotnet-services
docker buildx bake -f build/build.hcl node-services
docker buildx bake -f build/build.hcl java-services
```

Build groups: `default` (all), `dotnet-services`, `node-services`, `java-services`.

## Database

- `config/mysql.cnf` — MySQL server tuning, mounted into the MySQL container by `db.yml`.

## Process management

Supervisor configs baked into the image, under `build/stack/supervisor/`:

| File | Purpose |
|------|---------|
| `supervisord.conf` | Supervisor daemon settings |
| `dotnet_services.conf` | .NET service management |
| `node_services.conf` | Node.js service management |
| `java_services.conf` | Java service management |
