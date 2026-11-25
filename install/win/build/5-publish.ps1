# Stage 5: publishes the .NET services of DocSpace-server once in Release, as install/common/packages-build.sh does, keeps the NuGet
# packages several services share in a .NET package store, and lays every service (.NET, node, Java) out in out\Files.
. "$PSScriptRoot\lib\common.ps1"

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

# Node services with the production node_modules of 4-backend.ps1, and the Next.js apps of 3-frontend.ps1
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
