# Builds the ONLYOFFICE Apps Windows installers: runs the stages in order and stops at the first failure (exit code 1).
# Examples: build.ps1 (all stages)   build.ps1 -From publish   build.ps1 -Stages download,package   build.ps1 -Stages installer -Editions CE
# The stages up to copy are the functions below; download.ps1 and package.ps1 hold the two large ones.
[CmdletBinding()]
param (
    [string[]]$Stages,                  # names below; powershell -File passes "a,b" as one string, so lists are split here
    [string]$From,                      # this stage and all after it
    [string[]]$Editions = @('CE', 'EE', 'DE', 'Prereq')   # stage 'installer' only; 'package' always builds all
)

$ErrorActionPreference = 'Stop'
$Order = 'clean', 'mcp', 'plugins', 'frontend', 'backend', 'publish', 'copy', 'download', 'package'

function Split-List([string[]]$Values, [string[]]$Allowed, [string]$Name) {
    $items = @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $wrong = @($items | Where-Object { $Allowed -notcontains $_ })
    if ($wrong) { throw "-${Name}: unknown value(s) $($wrong -join ', '); allowed: $($Allowed -join ', ')" }
    return $items
}

# ---------------------------------------------------------------- clean
# Empties the outputs of the last build; downloads (out\downloads, out\redist) and the installer cache stay
function Clear-Outputs {
    foreach ($folder in (Join-Path $Paths.Out 'Files'), (Join-Path $Paths.Out 'OpenResty'), (Join-Path $Paths.Out 'OpenSearch'), (Join-Path $Paths.Out 'OpenSearchStack'),
        $Paths.Publish, $Paths.License, (Join-Path $Paths.Work 'plugins\publish'), (Join-Path $Paths.Work 'publish')) {
        if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Force | Remove-Item -Recurse -Force }
    }
    Remove-Item -Path (Join-Path $Paths.Installer '*.back*.aip') -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- mcp
# docspace-mcp into mcp\bin; package.ps1 copies it into products\ASC.AI\mcp
function Build-Mcp {
    Push-Location -LiteralPath (Join-Path $Paths.Work 'mcp')
    try {
        Invoke-Tool 'pnpm' @('install', '--frozen-lockfile')
        Invoke-Tool 'pnpm' @('build-app')
    }
    finally { Pop-Location }
    Assert-Paths 'mcp' @('mcp\bin\*')
}

# ---------------------------------------------------------------- plugins
# Every docspace-plugins plugin, its plugin.zip unpacked into plugins\publish\<package name>
function Build-Plugins {
    $repository = Join-Path $Paths.Work 'plugins'
    $publish = Join-Path $repository 'publish'
    $sevenzip = Get-ToolPath 'sevenzip'

    foreach ($folder in Get-ChildItem -LiteralPath $repository -Directory) {
        $package = Join-Path $folder.FullName 'package.json'
        if (-not (Test-Path -LiteralPath $package)) { continue }
        Write-Host "Building $($folder.Name)"
        Push-Location -LiteralPath $folder.FullName
        try {
            Invoke-Tool 'yarn' @('install') "yarn install ($($folder.Name))"
            Invoke-Tool 'yarn' @('run', 'build') "yarn run build ($($folder.Name))"
        }
        finally { Pop-Location }

        $zip = Join-Path $folder.FullName 'dist\plugin.zip'
        if (-not (Test-Path -LiteralPath $zip)) { Write-Host "WARNING: $($folder.Name) built no dist\plugin.zip, skipped"; continue }
        $name = (Get-Content -LiteralPath $package -Raw | ConvertFrom-Json).name
        $target = Join-Path $publish $name
        New-Folder $target
        Invoke-Tool $sevenzip @('x', $zip, "-o$target", '-y') "unpack $($folder.Name)\dist\plugin.zip"
    }
    Assert-Paths 'plugins' @('plugins\publish\*')
}

# ---------------------------------------------------------------- frontend
# DocSpace-client into publish\web; the Jenkins job may set NODE_OPTIONS and "parallel": 1 in client\nx.json for low memory
function Build-Frontend {
    $client = Join-Path $Paths.Work 'client'
    # A hoisted node_modules, as the Windows package copies the apps with their own node_modules
    Update-TextFile (Join-Path $client 'pnpm-workspace.yaml') '(?m)^# *nodeLinker: *hoisted' 'nodeLinker: hoisted'

    Push-Location -LiteralPath $client
    try {
        Invoke-Tool 'pnpm' @('install')
        Invoke-Tool 'pnpm' @('run', 'deploy')
    }
    finally { Pop-Location }
    Assert-Paths 'frontend' @('publish\web\public\*', 'publish\web\client\*', 'publish\web\login\*', 'publish\web\editor\*', 'publish\web\sdk\*', 'publish\web\management\*')
}

# ---------------------------------------------------------------- backend
# Production node_modules of the node services and the Identity jars of DocSpace-server; stage publish builds the .NET services once in Release
function Build-Backend {
    $common = Join-Path $Paths.Work 'server\common'
    foreach ($service in 'ASC.Socket.IO', 'ASC.AI.Chat', 'ASC.SsoAuth') {
        Push-Location -LiteralPath (Join-Path $common $service)
        try {
            # The lockfile is checked first, then the development dependencies are dropped
            Invoke-Tool 'yarn' @('install', '--frozen-lockfile') "yarn install ($service)"
            Invoke-Tool 'yarn' @('workspaces', 'focus', '--production') "yarn workspaces focus --production ($service)"
        }
        finally { Pop-Location }
    }

    Push-Location -LiteralPath (Join-Path $common 'ASC.Identity')
    try {
        Invoke-Tool 'mvn' @('clean', 'package', '-DskipTests', '-pl', 'authorization/authorization-container', '-am') 'mvn package (Identity authorization)'
        Invoke-Tool 'mvn' @('clean', 'package', '-DskipTests', '-pl', 'registration/registration-container', '-am') 'mvn package (Identity registration)'
    }
    finally { Pop-Location }
    Assert-Paths 'backend' @('server\common\ASC.Socket.IO\node_modules', 'server\common\ASC.AI.Chat\node_modules', 'server\common\ASC.SsoAuth\node_modules',
        'server\common\ASC.Identity\authorization\authorization-container\target\*.jar', 'server\common\ASC.Identity\registration\registration-container\target\*.jar')
}

# ---------------------------------------------------------------- publish
# The .NET services of DocSpace-server published once in Release, as install/common/packages-build.sh does, the NuGet packages several
# services share in a .NET package store, and every service (.NET, node, Java) laid out in out\Files
function Publish-Services {
    $server = Join-Path $Paths.Work 'server'
    $files = $Paths.Files
    $webPublish = Join-Path $Paths.Work 'publish\web'
    # ReleaseProfile puts every service into <workspace>\publish\services\<name>\service
    $dotnetPublish = Join-Path $Paths.Work 'publish\services'
    $runner = Join-Path $files 'services\ASC.Migration.Runner\service'
    $store = Join-Path $files 'dotnetstore'
    $publishArgs = @('-c', 'Release', '-r', 'win-x64', '--self-contained', 'false', '-p:DebugType=None', '-p:DebugSymbols=false')

    # The migration runner and the solution from scratch; the second pass leaves out the packages of the store (nothing compiles again)
    function Publish-Dotnet([string[]]$Manifest) {
        Remove-Folder $dotnetPublish, $runner
        Invoke-Tool 'dotnet' (@('publish', (Join-Path $server 'common\Tools\ASC.Migration.Runner\ASC.Migration.Runner.csproj')) + $publishArgs + $Manifest + @('-o', $runner)) 'dotnet publish ASC.Migration.Runner'
        Invoke-Tool 'dotnet' (@('publish', (Join-Path $server 'ASC.Web.slnx')) + $publishArgs + $Manifest + @('-p:PublishProfile=ReleaseProfile')) 'dotnet publish ASC.Web.slnx'
    }

    Publish-Dotnet @()
    & (Join-Path $Paths.Lib 'dotnet-store.ps1') -Action Build -PublishRoot $dotnetPublish -RunnerDir $runner -StoreDir $store
    if ($LASTEXITCODE -ne 0) { throw "dotnet-store.ps1 Build failed with exit code $LASTEXITCODE" }
    Publish-Dotnet @('--manifest', (Join-Path $store 'x64\net10.0\artifact.xml'))

    # Each published .NET service into its folder of the package; robocopy codes 8 and above are errors
    $services = [ordered]@{
        'ASC.Files' = 'products\ASC.Files\server'; 'ASC.People' = 'products\ASC.People\server'
        'ASC.AI' = 'products\ASC.AI\server'; 'ASC.AI.Worker' = 'products\ASC.AI\service'
        'ASC.ApiSystem' = 'services\ASC.ApiSystem\service'; 'ASC.Data.Backup' = 'services\ASC.Data.Backup\service'
        'ASC.Files.Worker' = 'services\ASC.Files.Worker\service'; 'ASC.Notify' = 'services\ASC.Notify\service'
        'ASC.Studio.Notify' = 'services\ASC.Studio.Notify\service'; 'ASC.Data.Backup.Worker' = 'services\ASC.Data.Backup.Worker\service'
        'ASC.TelegramService' = 'services\ASC.TelegramService\service'; 'ASC.ClearEvents' = 'services\ASC.ClearEvents\service'
        'ASC.Web.Api' = 'services\ASC.Web.Api\service'; 'ASC.Web.Studio' = 'services\ASC.Web.Studio\service'
        'ASC.Web.HealthChecks.UI' = 'services\ASC.Web.HealthChecks.UI\service'
    }
    foreach ($service in $services.Keys) {
        & robocopy.exe (Join-Path $dotnetPublish "$service\service") (Join-Path $files $services[$service]) /E /MOVE /NFL /NDL /NJH /NJS /NP
        if ($LASTEXITCODE -ge 8) { throw "Cannot move the published $service to $($services[$service]) (robocopy exit code $LASTEXITCODE)" }
    }

    # The services find the store through additionalProbingPaths; Apps.aip replaces {APPDIR} with the install folder in every service folder
    & (Join-Path $Paths.Lib 'dotnet-store.ps1') -Action SetProbingPaths -FilesDir $files -AipPath (Join-Path $Paths.Installer 'Apps.aip')
    if ($LASTEXITCODE -ne 0) { throw "dotnet-store.ps1 SetProbingPaths failed with exit code $LASTEXITCODE" }

    # Node services with the production node_modules of stage backend, and the Next.js apps of stage frontend
    foreach ($service in 'ASC.Socket.IO', 'ASC.AI.Chat', 'ASC.SsoAuth') {
        Copy-Tree (Join-Path $server "common\$service") (Join-Path $files "services\$service\service")
    }
    $apps = [ordered]@{ 'login' = 'products\ASC.Login\login'; 'editor' = 'products\ASC.Files\editor'; 'sdk' = 'products\ASC.Sdk\sdk'; 'management' = 'products\ASC.Management\management' }
    foreach ($app in $apps.Keys) { Copy-Tree (Join-Path $webPublish $app) (Join-Path $files $apps[$app]) }

    # Java services: the jar of each Identity container as app.jar
    foreach ($part in @{ 'authorization' = 'ASC.Identity.Authorization'; 'registration' = 'ASC.Identity.Registration' }.GetEnumerator()) {
        $jar = Get-ChildItem -Path (Join-Path $server "common\ASC.Identity\$($part.Key)\$($part.Key)-container\target\*.jar") | Select-Object -Last 1
        if (-not $jar) { throw "No jar of ASC.Identity $($part.Key); run stage backend first" }
        $target = Join-Path $files "services\$($part.Value)\service"
        New-Folder $target
        Copy-Item -LiteralPath $jar.FullName -Destination (Join-Path $target 'app.jar') -Force
    }

    $expected = @($services.Values | ForEach-Object { "buildtools\install\win\out\Files\$_\*.dll" }) + @(
        'buildtools\install\win\out\Files\services\ASC.Migration.Runner\service\ASC.Migration.Runner.exe',
        'buildtools\install\win\out\Files\dotnetstore\x64\net10.0\artifact.xml',
        'buildtools\install\win\out\Files\services\ASC.Socket.IO\service\*', 'buildtools\install\win\out\Files\services\ASC.AI.Chat\service\*',
        'buildtools\install\win\out\Files\services\ASC.SsoAuth\service\*', 'buildtools\install\win\out\Files\products\ASC.Login\login\*',
        'buildtools\install\win\out\Files\products\ASC.Files\editor\*', 'buildtools\install\win\out\Files\products\ASC.Sdk\sdk\*',
        'buildtools\install\win\out\Files\products\ASC.Management\management\*',
        'buildtools\install\win\out\Files\services\ASC.Identity.Authorization\service\app.jar', 'buildtools\install\win\out\Files\services\ASC.Identity.Registration\service\app.jar')
    Assert-Paths 'publish' $expected
}

# ---------------------------------------------------------------- copy
# The client, the campaign pages, the configs and the nginx configs into out\Files
function Copy-Frontend {
    $web = Join-Path $Paths.Work 'publish\web'
    $config = Join-Path $Paths.BuildTools 'config'
    $files = $Paths.Files

    Copy-Tree (Join-Path $web 'public') (Join-Path $files 'public')
    Copy-Tree (Join-Path $Paths.Work 'campaigns\src\campaigns') (Join-Path $files 'public\campaigns')
    Copy-Tree (Join-Path $web 'client') (Join-Path $files 'client')
    Copy-Tree (Join-Path $config 'nginx') (Join-Path $files 'nginx\conf')
    # The top level of config only; document-formats is a submodule with its own files
    Copy-Tree (Join-Path $config '*') (Join-Path $files 'config') -Flat
    Copy-Tree (Join-Path $config 'document-formats') (Join-Path $files 'config\document-formats') -Flat

    Assert-Paths 'copy' @('buildtools\install\win\out\Files\public\*', 'buildtools\install\win\out\Files\public\campaigns\*', 'buildtools\install\win\out\Files\client\*',
        'buildtools\install\win\out\Files\config\appsettings.json', 'buildtools\install\win\out\Files\config\document-formats\*', 'buildtools\install\win\out\Files\nginx\conf\onlyoffice.conf')
}

# ---------------------------------------------------------------- run
$Steps = @{ clean = { Clear-Outputs }; mcp = { Build-Mcp }; plugins = { Build-Plugins }; frontend = { Build-Frontend }; backend = { Build-Backend }
    publish = { Publish-Services }; copy = { Copy-Frontend }; download = { & (Join-Path $PSScriptRoot 'download.ps1') }
    package = { & (Join-Path $PSScriptRoot 'package.ps1') }; installer = { & (Join-Path $PSScriptRoot 'package.ps1') -InstallersOnly -Editions $Editions } }

try {
    $Editions = @(Split-List $Editions @('CE', 'EE', 'DE', 'Prereq') 'Editions')
    if ($Stages) { $Run = @(Split-List $Stages ($Order + 'installer') 'Stages' | Sort-Object { [array]::IndexOf(($Order + 'installer'), $_) } -Unique) }
    elseif ($From) { $Run = $Order[([array]::IndexOf($Order, @(Split-List $From $Order 'From')[0]))..($Order.Count - 1)] }
    else { $Run = $Order }
    if (($Run -contains 'package') -and ($Run -contains 'installer')) { throw "Stages 'package' and 'installer' exclude each other: 'package' already builds every installer" }
}
catch { Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1 }

$started = Get-Date
Write-Host "==== stages: $($Run -join ', ')" -ForegroundColor Cyan
Push-Location
try {
    # Paths, tools and the calls that stop the build; it also changes to the workspace folder
    . "$PSScriptRoot\lib\common.ps1"
    foreach ($stage in $Run) {
        $begin = Get-Date
        Write-Host "==== stage $stage" -ForegroundColor Cyan
        & $Steps[$stage]
        Write-Host ("==== stage {0} done in {1:N1} min" -f $stage, ((Get-Date) - $begin).TotalMinutes) -ForegroundColor Green
    }
}
catch {
    Write-Host "FAIL: stage $stage`: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    exit 1
}
finally { Pop-Location }
Write-Host ("DONE in {0:N0} min" -f ((Get-Date) - $started).TotalMinutes) -ForegroundColor Green
exit 0
