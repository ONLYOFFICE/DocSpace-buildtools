# Stage 8: finishes out\Files and the auxiliary components and builds the installers into out\publish.
# -InstallersOnly rebuilds only the chosen Apps editions on what an earlier full run of this stage left (stage 'installer' of build.ps1).
[CmdletBinding()]
param (
    [ValidateSet('CE', 'EE', 'DE', 'Prereq')][string[]]$Editions = @('CE', 'EE', 'DE', 'Prereq'),
    [switch]$InstallersOnly
)
. "$PSScriptRoot\lib\common.ps1"
$Versions = & "$PSScriptRoot\versions.ps1"

if (-not $env:BUILD_VERSION -or -not $env:BUILD_NUMBER) { throw 'BUILD_VERSION and BUILD_NUMBER must be set, e.g. 4.1 and 16' }
$Version = "$env:BUILD_VERSION.$env:BUILD_NUMBER"
$Sign = $env:SignBuild -eq 'true'
$AdvancedInstaller = Get-ToolPath 'AdvancedInstaller'
$Out = $Paths.Out
$Files = $Paths.Files
$Installer = $Paths.Installer
$Winsw = Join-Path $Paths.Runtime 'winsw'
$AppsAip = Join-Path $Installer 'Apps.aip'
$PrerequisitesAip = Join-Path $Installer 'Apps.Prerequisites.aip'

# The .aip projects and utils.ps1 name the component versions themselves; a mismatch with versions.ps1 builds an installer that misses files
function Test-ComponentVersions {
    $checks = @(
        @{ File = 'Apps.aip'; Pattern = 'OpenResty-([\d.]+)\.msi'; Expected = $Versions.OpenResty }
        @{ File = 'Apps.aip'; Pattern = 'OpenSearch-([\d.]+)\.exe'; Expected = $Versions.OpenSearch }
        @{ File = 'Apps.Prerequisites.aip'; Pattern = 'OpenResty-([\d.]+)\.msi'; Expected = $Versions.OpenResty }
        @{ File = 'Apps.Prerequisites.aip'; Pattern = 'OpenSearch-([\d.]+)\.exe'; Expected = $Versions.OpenSearch }
        @{ File = 'OpenSearchStack.aip'; Pattern = 'opensearch-dashboards-([\d.]+)-windows-x64\.zip'; Expected = $Versions.OpenSearchDashboards }
        @{ File = 'OpenSearchStack.aip'; Pattern = 'fluent-bit-([\d.]+)-win64\.zip'; Expected = $Versions.FluentBit }
        @{ File = 'utils.ps1'; Pattern = 'Data\\Index\\v([\d.]+)'; Expected = $Versions.OpenSearch }
    )
    $problems = foreach ($check in $checks) {
        $found = @([regex]::Matches([IO.File]::ReadAllText((Join-Path $Installer $check.File)), $check.Pattern) | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        if ($found.Count -eq 0) { "$($check.File): no $($check.Pattern)" }
        elseif ($found.Count -ne 1 -or $found[0] -ne $check.Expected) { "$($check.File): $($found -join ', ') instead of $($check.Expected) ($($check.Pattern))" }
    }
    if ($problems) { throw "Component versions disagree with build\versions.ps1:`n  $($problems -join "`n  ")" }
    Write-Host 'Component versions of the projects match build\versions.ps1'
}

function Invoke-AdvancedInstaller([string[]]$Arguments) { Invoke-Tool $AdvancedInstaller $Arguments "AdvancedInstaller $($Arguments -join ' ')" }

# OpenSearch with the plugins Apps uses, OpenResty, the WinSW wrappers, configs and the client parts not needed at runtime removed
function Initialize-Files {
    $sevenzip = Get-ToolPath 'sevenzip'
    $opensearch = $Versions.OpenSearch
    $openresty = $Versions.OpenResty
    $extracted = Join-Path $Out "opensearch-$opensearch"
    Invoke-Tool $sevenzip @('x', (Join-Path $Paths.Downloads "opensearch-$opensearch.zip"), "-o$Out", '-y') 'unpack OpenSearch'
    Invoke-Tool $sevenzip @('x', (Join-Path $Paths.Downloads "ingest-attachment-$opensearch.zip"), "-o$Out\OpenSearch\plugins\ingest-attachment", '-y') 'unpack ingest-attachment'
    foreach ($plugin in 'opensearch-security', 'opensearch-job-scheduler', 'opensearch-index-management', 'opensearch-knn', 'opensearch-neural-search') {
        Copy-Tree (Join-Path $extracted "plugins\$plugin") (Join-Path $Out "OpenSearch\plugins\$plugin")
    }
    Remove-Folder (Join-Path $extracted 'plugins')
    Copy-Tree $extracted (Join-Path $Out 'OpenSearch')
    Remove-Folder $extracted
    Invoke-Tool $sevenzip @('x', (Join-Path $Paths.Downloads "openresty-$openresty.zip"), "-o$Out", '-y') 'unpack OpenResty'
    Copy-Tree (Join-Path $Out "openresty-$openresty-win64") (Join-Path $Out 'OpenResty')
    Remove-Folder (Join-Path $Out "openresty-$openresty-win64")

    New-Folder "$Out\OpenSearch\tools", "$Out\OpenResty\tools", "$Out\OpenResty\logs", "$Out\OpenSearchStack\tools"
    New-Folder @('tools', 'Logs', 'Data', 'sbin', 'nginx\conf\includes' | ForEach-Object { Join-Path $Files $_ })
    foreach ($service in 'products\ASC.Files\server', 'products\ASC.People\server', 'services\ASC.Data.Backup\service', 'services\ASC.Notify\service',
        'services\ASC.Files.Worker\service', 'services\ASC.Studio.Notify\service', 'services\ASC.Data.Backup.Worker\service', 'services\ASC.ClearEvents\service',
        'services\ASC.ApiSystem\service', 'services\ASC.Web.Api\service', 'services\ASC.Web.Studio\service', 'services\ASC.Web.HealthChecks.UI\service') {
        New-Folder (Join-Path $Files "$service\temp")
    }
    Copy-Tree (Join-Path $Paths.Work 'plugins\publish\*') (Join-Path $Files 'Data\Studio\webplugins') -Empty
    Copy-Tree (Join-Path $Paths.Work 'mcp\bin\*') (Join-Path $Files 'products\ASC.AI\mcp') -Empty

    # WinSW: OpenResty keeps the .NET 4 build, the other services run on WinSW 3
    Copy-Item (Join-Path $Winsw 'WinSW.NET4.exe') "$Out\OpenResty\tools\OpenResty.exe" -Force
    Copy-Item (Join-Path $Winsw 'OpenResty.xml') "$Out\OpenResty\tools\OpenResty.xml" -Force
    $wrappers = [ordered]@{
        "$Out\OpenSearch\tools"      = @('OpenSearch')
        "$Out\OpenSearchStack\tools" = @('OpenSearchDashboards')
        "$Files\tools"               = @('Socket.IO', 'AI.Chat', 'SsoAuth', 'DocEditor', 'Login', 'Sdk', 'MCP', 'Management', 'Identity.Authorization', 'Identity.Registration')
    }
    foreach ($folder in $wrappers.Keys) {
        foreach ($service in $wrappers[$folder]) {
            Copy-Item (Join-Path $Winsw 'WinSW3.0.0.exe') (Join-Path $folder "$service.exe") -Force
            Copy-Item (Join-Path $Winsw "$service.xml") (Join-Path $folder "$service.xml") -Force
        }
    }

    $docker = Join-Path $Paths.BuildTools 'install\docker\config'
    $nginx = Join-Path $Files 'nginx\conf'
    Copy-Item (Join-Path $Paths.Runtime 'nginx.conf') (Join-Path $nginx 'nginx.conf') -Force
    Copy-Item "$docker\nginx\proxy\onlyoffice-proxy.conf" (Join-Path $nginx 'onlyoffice-proxy.conf') -Force
    Copy-Item "$docker\nginx\proxy\onlyoffice-proxy.conf" (Join-Path $nginx 'onlyoffice-proxy.conf.tmpl') -Force
    Copy-Item "$docker\nginx\proxy\onlyoffice-proxy-ssl.conf" (Join-Path $nginx 'onlyoffice-proxy-ssl.conf.tmpl') -Force
    Copy-Item "$docker\nginx\proxy\letsencrypt.conf" (Join-Path $nginx 'includes\letsencrypt.conf') -Force
    Copy-Item (Join-Path $Paths.Runtime 'sbin\apps-ssl-setup.ps1') (Join-Path $Files 'sbin\apps-ssl-setup.ps1') -Force
    Copy-Item "$docker\fluent-bit.conf" (Join-Path $Files 'config\fluent-bit.conf') -Force

    & (Join-Path $Paths.Lib 'configure-files.ps1') -FilesDir $Files -Version $Version

    # Source maps, type declarations in node_modules, debug symbols and the translation tool metadata are not needed at runtime
    $unused = @(Get-ChildItem -LiteralPath $Files -Recurse -File | Where-Object {
        $_.Name -match '\.(js|mjs|cjs|css|ts|mts|cts)\.map$' -or $_.Extension -eq '.pdb' -or ($_.Name -match '\.d\.[cm]?ts$' -and $_.FullName -match '\\node_modules\\') })
    $unused | Remove-Item -Force
    Write-Host "Removed $($unused.Count) source maps, type declarations and debug symbols"
    $meta = @(Get-ChildItem -LiteralPath $Files -Recurse -Directory -Force -Filter '.meta' | Where-Object { $_.Parent.Name -eq 'locales' })
    $meta | Remove-Item -Recurse -Force
    Write-Host "Removed $($meta.Count) locales\.meta folders"
    # One copy of the node_modules packages the Next.js apps share
    & (Join-Path $Paths.Lib 'dedupe-node-modules.ps1') -FilesDir $Files
}

# Utils.CA.dll: the C# custom actions (port, Redis and RabbitMQ checks)
function Build-CustomActions {
    $utils = Join-Path $Installer 'CustomActions\C#\Utils'
    # nuget takes the package folder of DocSpace-server from the NuGet.config in the workspace
    Update-TextFile (Join-Path $Paths.Work 'server\NuGet.config') '\.nuget\\packages' 'server\.nuget\packages' (Join-Path $Paths.Work 'NuGet.config')
    Invoke-Tool (Join-Path $Paths.Downloads 'nuget.exe') @('install', (Join-Path $utils 'packages.config'), '-OutputDirectory', (Join-Path $utils 'packages')) 'nuget install (custom actions)'
    Invoke-Tool (Get-ToolPath 'msbuild') @((Join-Path $utils 'Utils.csproj')) 'msbuild Utils.csproj'
    Copy-Item (Join-Path $utils 'bin\Debug\Utils.CA.dll') (Join-Path $Out 'Utils.CA.dll') -Force
    Remove-Folder (Join-Path $utils 'bin'), (Join-Path $utils 'obj')
}

# OpenResty, OpenSearch and OpenSearchStack are reused from the cache when their inputs did not change
function Build-AuxInstaller([string]$Project, [string]$Package, [string]$Version) {
    $cache = @{ Project = $Project; Package = $Package; Inputs = @($Project) }
    if ($Version) { $cache.Version = $Version }
    & (Join-Path $Paths.Lib 'aux-installers-cache.ps1') -Action Restore @cache
    if ($LASTEXITCODE -eq 0) { return }
    $aip = Join-Path $Installer "$Project.aip"
    if ($Version) { Invoke-AdvancedInstaller @('/edit', $aip, '/SetVersion', $Version) }
    if ($Sign) { Invoke-AdvancedInstaller @('/edit', $aip, '/SetSig') }
    Invoke-AdvancedInstaller @('/rebuild', $aip)
    & (Join-Path $Paths.Lib 'aux-installers-cache.ps1') -Action Save @cache
}

# The license of each edition goes to out\license, which Apps.aip shows; Resources keeps the texts of every edition unchanged
function Build-Apps {
    $builds = [ordered]@{ CE = @('APPS_COMMUNITY', 'Community'); EE = @('APPS_ENTERPRISE', 'Enterprise'); DE = @('APPS_DEVELOPER', 'Developer') }
    Invoke-AdvancedInstaller @('/edit', $AppsAip, '/SetVersion', $Version)
    if ($Editions -contains 'Prereq') { Invoke-AdvancedInstaller @('/edit', $PrerequisitesAip, '/SetVersion', $Version) }
    if ($Sign) {
        Invoke-AdvancedInstaller @('/edit', $AppsAip, '/SetSig')
        if ($Editions -contains 'Prereq') { Invoke-AdvancedInstaller @('/edit', $PrerequisitesAip, '/SetSig') }
    }
    New-Folder $Paths.License
    foreach ($edition in $builds.Keys) {
        if ($Editions -notcontains $edition) { continue }
        $name = $builds[$edition][1]
        Copy-Item (Join-Path $Installer "Resources\License_$name.rtf") (Join-Path $Paths.License 'License.rtf') -Force
        Copy-Item (Join-Path $Installer "Resources\License_${name}_Redist.rtf") (Join-Path $Paths.License 'License_Redist.rtf') -Force
        Invoke-AdvancedInstaller @('/rebuild', $AppsAip, '-buildslist', $builds[$edition][0])
    }
    if ($Editions -contains 'Prereq') { Invoke-AdvancedInstaller @('/rebuild', $PrerequisitesAip, '-buildslist', 'DefaultBuild') }
}

Test-ComponentVersions
if ($InstallersOnly) {
    Assert-Paths 'installer' @('buildtools\install\win\out\Files\config\appsettings.json', 'buildtools\install\win\out\Utils.CA.dll',
        'buildtools\install\win\out\MySQL Installer Runner.exe', 'buildtools\install\win\out\publish\OpenResty-*.msi', 'buildtools\install\win\out\publish\OpenSearch-*.exe',
        'buildtools\install\win\out\publish\OpenSearchStack.msi')
}
else {
    if ($Sign) {
        $signingTool = Join-Path $Paths.Work 'cloudhsm\signing-tool.ps1'
        if (-not (Test-Path -LiteralPath $signingTool)) { throw "Signing needs $signingTool" }
        Copy-Item $signingTool (Join-Path $Out 'signing-tool.ps1') -Force
    }
    Remove-Folder $Paths.Publish
    Initialize-Files
    Build-CustomActions
    Remove-Item -Path (Join-Path $Installer '*.back.*') -Force -ErrorAction SilentlyContinue
    Invoke-Tool 'iscc' @('/Qp', "/O$Out", (Join-Path $Installer 'MySQL Server Installer Runner.iss')) 'iscc MySQL Server Installer Runner.iss'
    Build-AuxInstaller 'OpenResty' "OpenResty-$($Versions.OpenResty).msi" $Versions.OpenResty
    Build-AuxInstaller 'OpenSearch' "OpenSearch-$($Versions.OpenSearch).exe" ''
    Build-AuxInstaller 'OpenSearchStack' 'OpenSearchStack.msi' ''
}
Build-Apps

$names = @{ CE = 'Community'; EE = 'Enterprise'; DE = 'Developer'; Prereq = 'Prerequisites' }
$built = @($Editions | ForEach-Object { "buildtools\install\win\out\publish\ONLYOFFICE_Apps_$($names[$_])_Win-install.v$Version*.exe" })
$auxiliary = if ($InstallersOnly) { @() } else { @("buildtools\install\win\out\publish\OpenResty-$($Versions.OpenResty).msi",
    "buildtools\install\win\out\publish\OpenSearch-$($Versions.OpenSearch).exe", 'buildtools\install\win\out\publish\OpenSearchStack.msi') }
Assert-Paths $(if ($InstallersOnly) { 'installer' } else { 'package' }) ($built + $auxiliary)
