# Windows installers

This folder builds the Windows installers of ONLYOFFICE Apps with [Advanced Installer](https://www.advancedinstaller.com/)
(22.3 or newer) and Inno Setup:

- `ONLYOFFICE_Apps_Community_Win-install.v<version>.exe`, `..._Enterprise_...`, `..._Developer_...`: the product;
- `ONLYOFFICE_Apps_Prerequisites_Win-install.v<version>.exe`: the third-party components the product needs;
- `OpenResty-<version>.msi`, `OpenSearch-<version>.exe`, `OpenSearchStack.msi`, `MySQL Installer Runner.exe`: auxiliary
  installers that the two above bundle.

## Layout

```
install/win/
├── build/                      build stages, run in this order
│   ├── mcp-build.bat           1. docspace-mcp
│   ├── plugins-build.ps1       2. docspace-plugins
│   ├── frontend-build.bat      3. DocSpace-client
│   ├── backend-build.bat       4. node and Java services of DocSpace-server
│   ├── publish-script.bat      5. .NET services of DocSpace-server, then every service into out\Files
│   ├── frontend-copy.bat       6. client, configs and nginx configs into out\Files
│   ├── build-download-prereq.ps1  7. Docs, build tools and prerequisites into out\
│   ├── build-batch.bat         8. finishes out\Files and builds every installer into out\publish
│   └── lib/                    helpers the stages call, never called directly
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
│   └── Resources/              license agreements, dialog images, icon
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
| `out\Files\` | stages 4-6, `build-batch.bat` | the installed product (`APPDIR`), synchronized into `Apps.aip` |
| `out\downloads\` | `build-download-prereq.ps1` | Docs EXEs, `nuget.exe`, OpenSearch/OpenResty archives |
| `out\redist\` | `build-download-prereq.ps1` | the payload of the Prerequisites EXE (every `https://` link in `Apps.aip`) |
| `out\OpenResty\`, `out\OpenSearch\`, `out\OpenSearchStack\` | `build-batch.bat` | inputs of the auxiliary projects |
| `out\Utils.CA.dll`, `out\MySQL Installer Runner.exe`, `out\signing-tool.ps1` | `build-batch.bat` | embedded or used by the projects |
| `out\publish\` | Advanced Installer | the installers |

Downloads are kept between builds and checked against the server size; `Files`, `OpenResty`, `OpenSearch`,
`OpenSearchStack` and `publish` must be emptied before a new build.

## Running a build

The stages run from a workspace root that holds the repositories side by side:

| Folder | Repository |
|---|---|
| `buildtools` | DocSpace-buildtools (with submodules) |
| `server` | DocSpace-server |
| `client` | DocSpace-client |
| `campaigns` | ASC.Web.Campaigns |
| `plugins` | docspace-plugins |
| `mcp` | docspace-mcp |
| `cloudhsm` | signing scripts, only for a signed build |

Tools and parameters come from environment variables: `sevenzip`, `sed` (GNU sed), `msbuild`, `AdvancedInstaller`
(paths, quoted), `BUILD_VERSION` (`4.1`), `BUILD_NUMBER`, `SignBuild` (`true` to sign), `DOCUMENT_SERVER_VERSION_CE|EE|DE`
(`latest` or `custom` with `DOCUMENT_SERVER_CE|EE|DE_CUSTOM_LINK`), optionally `APPS_WIN_BUILD_CACHE` (cache of the auxiliary
installers, default `win-build-cache` in the workspace). `iscc`, `dotnet`, `node`, `pnpm`, `yarn`, `mvn` and `java` must be in
`PATH`; `Utils.csproj` also needs WiX Toolset 3.x.

```bat
set "AppsWin=buildtools\install\win"
call %AppsWin%\build\mcp-build.bat %cd%\mcp
powershell -File %AppsWin%\build\plugins-build.ps1 plugins
call %AppsWin%\build\frontend-build.bat %cd%\client
call %AppsWin%\build\backend-build.bat %cd%\server
call %AppsWin%\build\publish-script.bat %cd%\server %cd%\%AppsWin%\out\Files
call %AppsWin%\build\frontend-copy.bat %cd% %cd%\%AppsWin%\out\Files
powershell -File %AppsWin%\build\build-download-prereq.ps1
call %AppsWin%\build\build-batch.bat
```

The `.bat` files do not stop on most errors and do not always return an error code: check that each stage produced its
files. The server and client builds also leave `publish\` in the workspace root, which `publish-script.bat` and
`frontend-copy.bat` read.

A build changes tracked files: `ProductVersion` and `DS_VERSION` in the `.aip` projects, the Docs arguments in `Apps.aip`
(`docs-secret-args.ps1`) and `Resources\License.rtf`, `Resources\License_Redist.rtf` (the edition licenses are copied over
them). Do not commit these changes.

## Changing things

- A component version is set in several places that must agree: OpenSearch and OpenResty in `build-batch.bat`,
  `build-download-prereq.ps1` and the `SetupFileUrl` of `Apps.aip` and `Apps.Prerequisites.aip`; the other prerequisites in
  the prerequisite rows of `Apps.aip` (download link, detection) and `Apps.Prerequisites.aip` (`..\out\redist\<file>`).
- A new Apps service wrapped by WinSW needs its config in `runtime\winsw\`, its name in `AppsServices` of `build-batch.bat`
  and its service row in `Apps.aip`. A new .NET service also needs its `publish-script.bat` line, its entry in
  `PackagedServices` of `lib\dotnet-store.ps1` and a runtimeconfig `TxtUpdate` row in `Apps.aip`: `publish-script.bat`
  stops when that row is missing.
- Open the `.aip` projects with the Advanced Installer version they were saved with or a newer one (`version` of their
  `<DOCUMENT>` element); an older version cannot open them.
- Variables set in the `.bat` files reach every program they start, and MSBuild reads them as properties: keep the `Apps`
  prefix of `build-batch.bat` (a plain `OutDir` moved the `Utils.csproj` output, a plain `WinDir` would replace `%WINDIR%`).
- `build\*.bat` must keep CRLF line endings (`.gitattributes`): `cmd.exe` does not find labels reliably in LF files.
