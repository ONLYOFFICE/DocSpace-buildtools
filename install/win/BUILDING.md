# Building the Windows installers

For developers. How to install the product is in [README.md](README.md).

This folder builds the Windows installers of ONLYOFFICE Apps with [Advanced Installer](https://www.advancedinstaller.com/)
(22.3 or newer) and Inno Setup:

- `ONLYOFFICE_Apps_Community_Win-install.v<version>.exe`, `..._Enterprise_...`, `..._Developer_...`: the product;
- `ONLYOFFICE_Apps_Prerequisites_Win-install.v<version>.exe`: the third-party components the product needs;
- `OpenResty-<version>.msi`, `OpenSearch-<version>.exe`, `OpenSearchStack.msi`, `MySQL Installer Runner.exe`: auxiliary
  installers that the two above bundle.

## Layout

```
install/win/
├── build/                      PowerShell, one script per stage, run in this order by build.ps1
│   ├── build.ps1               entry point: build.ps1 [-Stages a,b | -From stage] [-Editions CE,EE,DE,Prereq]
│   ├── versions.ps1            versions of OpenSearch, OpenSearch Dashboards, OpenResty and Fluent Bit
│   ├── 1-mcp.ps1               docspace-mcp into mcp\bin
│   ├── 2-plugins.ps1           docspace-plugins into plugins\publish
│   ├── 3-frontend.ps1          DocSpace-client into publish\web
│   ├── 4-backend.ps1           node_modules of the node services and the Identity jars of DocSpace-server
│   ├── 5-publish.ps1           .NET services (with a shared package store), then every service into out\Files
│   ├── 6-copy-frontend.ps1     client, campaigns, configs and nginx configs into out\Files
│   ├── 7-download.ps1          Docs, nuget.exe, archives and the Prerequisites payload into out\
│   ├── 8-package.ps1           finishes out\Files and builds every installer into out\publish
│   └── lib/                    helpers of the stages, never called directly
│       ├── common.ps1                 paths, tools, calls that stop the build on failure
│       ├── configure-files.ps1        adapts the configs in out\Files to Windows (OpenResty, Fluent Bit, log levels, URLs)
│       ├── aux-installers-cache.ps1   reuses OpenResty/OpenSearch/OpenSearchStack builds between runs
│       ├── dedupe-node-modules.ps1    one copy of the node_modules packages the Next.js apps share
│       ├── docs-secret-args.ps1       Docs command line by the bundled Docs version
│       └── dotnet-store.ps1           .NET runtime package store shared by the services
├── installer/                  installer projects and what they embed
│   ├── Apps.aip                Community, Enterprise and Developer (builds APPS_COMMUNITY, APPS_ENTERPRISE, APPS_DEVELOPER)
│   ├── Apps.Prerequisites.aip  Prerequisites
│   ├── OpenResty.aip, OpenSearch.aip, OpenSearchStack.aip
│   ├── MySQL Server Installer Runner.iss
│   ├── utils.ps1               PowerShell custom actions of Apps.aip (configuration, secrets, ACLs)
│   ├── CustomActions/          C# custom actions (Utils.CA.dll: port and connection checks)
│   └── Resources/              license agreements of each edition (License_<Edition>.rtf), dialog images, icon
├── runtime/                    files copied as they are into the installed product
│   ├── nginx.conf              main OpenResty config
│   ├── sbin/                   apps-ssl-setup.ps1 (HTTPS and Let's Encrypt)
│   └── winsw/                  WinSW binaries and one service config per wrapped service
└── out/                        everything downloaded or built (ignored by git)
```

The paths in the `.aip` projects are relative to `installer/`: their input is `..\out\Files`, `..\out\redist`, ...,
their packages go to `..\out\publish`.

### out/

| Path | Written by | Contents |
|---|---|---|
| `out\Files\` | stages 5, 6, 8 | the installed product (`APPDIR`), synchronized into `Apps.aip` |
| `out\downloads\` | stage 7 | Docs EXEs, `nuget.exe`, OpenSearch/OpenResty archives |
| `out\redist\` | stage 7 | the payload of the Prerequisites EXE (every `https://` link in `Apps.aip`) |
| `out\OpenResty\`, `out\OpenSearch\`, `out\OpenSearchStack\` | stages 7, 8 | inputs of the auxiliary projects |
| `out\license\` | stage 8 | the license of the edition being built, which `Apps.aip` shows |
| `out\Utils.CA.dll`, `out\MySQL Installer Runner.exe`, `out\signing-tool.ps1` | stage 8 | embedded or used by the projects |
| `out\publish\` | Advanced Installer | the installers |

Stage `clean` empties `Files`, `OpenResty`, `OpenSearch`, `OpenSearchStack`, `license` and `publish` (and `plugins\publish`,
`publish` in the workspace). Downloads are kept between builds and checked against the server size.

## Running a build

The stages run in a workspace that holds the repositories side by side; `build.ps1` finds it from its own location:

| Folder | Repository |
|---|---|
| `buildtools` | DocSpace-buildtools (with submodules) |
| `server` | DocSpace-server |
| `client` | DocSpace-client |
| `campaigns` | ASC.Web.Campaigns |
| `plugins` | docspace-plugins |
| `mcp` | docspace-mcp |
| `cloudhsm` | signing scripts, only for a signed build |

Tools and parameters come from environment variables:

| Variable | Used by | Value |
|---|---|---|
| `sevenzip`, `msbuild`, `AdvancedInstaller` | 2, 8 | paths of the tools (quotes allowed) |
| `BUILD_VERSION`, `BUILD_NUMBER` | 8 | `4.1` and the build number |
| `SignBuild` | 8 | `true` to sign (copies `cloudhsm\signing-tool.ps1`, signs with Advanced Installer) |
| `DOCUMENT_SERVER_VERSION_CE`, `_EE`, `_DE` | 7 | `latest` or `custom` with `DOCUMENT_SERVER_CE_CUSTOM_LINK` (`_EE_`, `_DE_`) |
| `APPS_WIN_BUILD_CACHE` | 8 | cache of the auxiliary installers, default `win-build-cache` in the workspace |
| `NODE_OPTIONS` | 3 | e.g. `--max-old-space-size=3072` on hosts with little memory |

`iscc`, `dotnet`, `node`, `pnpm`, `yarn`, `mvn` and `java` must be in `PATH`; `Utils.csproj` also needs WiX Toolset 3.x.

```powershell
powershell -ExecutionPolicy Bypass -File buildtools\install\win\build\build.ps1                          # all stages, clean first
powershell -ExecutionPolicy Bypass -File buildtools\install\win\build\build.ps1 -From publish            # resume after a failure
powershell -ExecutionPolicy Bypass -File buildtools\install\win\build\build.ps1 -Stages download,package
powershell -ExecutionPolicy Bypass -File buildtools\install\win\build\build.ps1 -Stages installer -Editions CE
```

Every stage stops at the first failing command and checks at its end that it produced its files, so `build.ps1` exits with 1
on the first broken stage. Stage `installer` rebuilds only the chosen editions on what an earlier `package` left (`Files`,
`Utils.CA.dll`, the auxiliary installers); it is not part of a full run.

A build still edits tracked files: `ProductVersion` and `DS_VERSION` in the `.aip` projects and the Docs arguments in `Apps.aip`
(`docs-secret-args.ps1`). Do not commit these changes. The license texts in `Resources\` stay as they are: stage 8 copies the
license of each edition into `out\license\`.

## Changing things

- **A component version** (OpenSearch, OpenSearch Dashboards, OpenResty, Fluent Bit): change `build\versions.ps1`, then the
  projects. Stage 8 stops with the list of places that disagree: the file names in `Apps.aip`, `Apps.Prerequisites.aip` and
  `OpenSearchStack.aip` and the index folder in `utils.ps1`; the other fields of those prerequisites (name, minimum version,
  detection) are edited in Advanced Installer. The other prerequisites live only in the prerequisite rows of `Apps.aip`
  (download link, detection) and `Apps.Prerequisites.aip` (`..\out\redist\<file>`).
- **A new Apps service wrapped by WinSW**: its config in `runtime\winsw\`, its name in the wrapper list of `8-package.ps1` and its
  service row in `Apps.aip`. A new .NET service also needs its folder in `5-publish.ps1`, its entry in `PackagedServices` of
  `lib\dotnet-store.ps1` and a runtimeconfig `TxtUpdate` row in `Apps.aip`: stage 5 stops when that row is missing.
- **A config change for Windows**: `lib\configure-files.ps1`, which edits the files line by line like the GNU sed calls it
  replaced (their output is kept byte for byte: LF line ends, the BOM of a file).
- Open the `.aip` projects with the Advanced Installer version they were saved with or a newer one (`version` of their
  `<DOCUMENT>` element); an older version cannot open them.
