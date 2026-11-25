# Keeps the NuGet packages that several .NET services use once, in a .NET runtime package store, instead of in every service folder.
# Build: reads the package lists of a first, ordinary publish (its deps.json files) and builds the store; publishing again with
# --manifest <store>\x64\net10.0\artifact.xml then leaves those packages out.
# SetProbingPaths: points every published service at the store; the installer replaces {APPDIR} with the install folder.
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][ValidateSet('Build', 'SetProbingPaths')][string]$Action,
    [string]$PublishRoot,
    [string]$RunnerDir,
    [string]$StoreDir,
    [string]$FilesDir,
    [string]$AipPath,
    [int]$MinServices = 2,
    [string]$ProbingPath = '{APPDIR}dotnetstore/x64/net10.0'
)

$ErrorActionPreference = 'Stop'
$Framework = 'net10.0'
$Runtime = 'win-x64'
# dotnet store fails on these with MSB3094 (several native files per name); they stay in the service folders.
$NotStorable = @('librdkafka.redist')
# The services publish-script.bat moves into the package; the solution publish also has projects the package does not ship.
$PackagedServices = @('ASC.Files', 'ASC.People', 'ASC.AI', 'ASC.AI.Worker', 'ASC.ApiSystem', 'ASC.Data.Backup', 'ASC.Files.Worker', 'ASC.Notify',
    'ASC.Studio.Notify', 'ASC.Data.Backup.Worker', 'ASC.TelegramService', 'ASC.ClearEvents', 'ASC.Web.Api', 'ASC.Web.Studio', 'ASC.Web.HealthChecks.UI')

if ($Action -eq 'Build') {
    $PublishDirs = @($PackagedServices | ForEach-Object { Join-Path $PublishRoot "$_\service" }) + @($RunnerDir)
    # The deps.json of the publish lists what the services load; the build one also has development dependencies that publish drops.
    $Usage = @{}
    $Services = 0
    foreach ($Dir in $PublishDirs) {
        if (-not (Test-Path -LiteralPath $Dir)) { throw "$Dir does not exist" }
        foreach ($Deps in Get-ChildItem -LiteralPath $Dir -File -Filter '*.deps.json') {
            if (-not (Test-Path -LiteralPath (Join-Path $Dir ($Deps.Name -replace '\.deps\.json$', '.runtimeconfig.json')))) { continue }
            $Services++
            foreach ($Library in (Get-Content -LiteralPath $Deps.FullName -Raw | ConvertFrom-Json).libraries.PSObject.Properties) {
                if ($Library.Value.type -ne 'package') { continue }
                if (-not $Usage.ContainsKey($Library.Name)) { $Usage[$Library.Name] = 0 }
                $Usage[$Library.Name]++
            }
        }
    }
    $Shared = @($Usage.Keys | Where-Object { $Usage[$_] -ge $MinServices -and $NotStorable -notcontains ($_ -split '/')[0] } | Sort-Object)
    if (-not $Shared) { throw 'No package is shared by the services' }

    $WorkDir = Join-Path ([IO.Path]::GetTempPath()) ('dotnet-store-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
    try {
        # A project cannot reference two versions of one package, so every further version goes into its own manifest.
        $Manifests = @{}
        foreach ($Group in ($Shared | Group-Object { ($_ -split '/')[0] })) {
            $Index = 0
            foreach ($Key in ($Group.Group | Sort-Object { $Usage[$_] } -Descending)) {
                $Name, $Version = $Key -split '/', 2
                if (-not $Manifests.ContainsKey($Index)) { $Manifests[$Index] = New-Object System.Collections.Generic.List[string] }
                $Manifests[$Index].Add("    <PackageReference Include=`"$Name`" Version=`"[$Version]`" />")
                $Index++
            }
        }
        $ManifestArgs = @()
        foreach ($Index in ($Manifests.Keys | Sort-Object)) {
            $Path = Join-Path $WorkDir "store-manifest-$Index.csproj"
            $Text = "<Project Sdk=`"Microsoft.NET.Sdk`">`n  <PropertyGroup><TargetFramework>$Framework</TargetFramework></PropertyGroup>`n  <ItemGroup>`n" + ($Manifests[$Index] -join "`n") + "`n  </ItemGroup>`n</Project>`n"
            [IO.File]::WriteAllText($Path, $Text)
            $ManifestArgs += @('-m', $Path)
        }

        if (Test-Path -LiteralPath $StoreDir) { Remove-Item -LiteralPath $StoreDir -Recurse -Force }
        & dotnet store @ManifestArgs -f $Framework -r $Runtime -o $StoreDir -w (Join-Path $WorkDir 'work') --skip-optimization --skip-symbols
        if ($LASTEXITCODE -ne 0) { throw "dotnet store failed with exit code $LASTEXITCODE" }
        $Artifact = Join-Path $StoreDir "x64\$Framework\artifact.xml"
        if (-not (Test-Path -LiteralPath $Artifact)) { throw "$Artifact was not created" }
        $StoreFiles = @(Get-ChildItem -LiteralPath $StoreDir -Recurse -File)
        Write-Host ("Package store: {0} of {1} packages shared by {2}+ of {3} services, {4} files, {5} MB" -f $Shared.Count, $Usage.Count, $MinServices, $Services, $StoreFiles.Count, [int](($StoreFiles | Measure-Object Length -Sum).Sum / 1MB))
    }
    finally {
        Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 0
}

# SetProbingPaths: every runtimeconfig.json of the .NET services gets the store as an additional probing path.
$FilesDir = (Resolve-Path -LiteralPath $FilesDir).ProviderPath.TrimEnd('\')
$Configs = @(foreach ($Folder in 'products', 'services') {
    Get-ChildItem -LiteralPath (Join-Path $FilesDir $Folder) -Recurse -File -Filter '*.runtimeconfig.json' | Where-Object { $_.FullName -notlike '*\node_modules\*' }
})
if ($Configs.Count -eq 0) { throw "No runtimeconfig.json found under $FilesDir" }
foreach ($Config in $Configs) {
    $Json = Get-Content -LiteralPath $Config.FullName -Raw | ConvertFrom-Json
    $Json.runtimeOptions | Add-Member -NotePropertyName additionalProbingPaths -NotePropertyValue @($ProbingPath) -Force
    [IO.File]::WriteAllText($Config.FullName, ($Json | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}
Write-Host "Probing path $ProbingPath set in $($Configs.Count) runtimeconfig.json files"

# A service folder without a TxtUpdate row in Apps.aip would keep {APPDIR} in its runtimeconfig.json and fail to load the store packages.
if ($AipPath) {
    $Rows = ([xml](Get-Content -LiteralPath $AipPath -Raw)).DOCUMENT.COMPONENT
    $Directories = @{}
    foreach ($Row in ($Rows | Where-Object { $_.cid -eq 'caphyon.advinst.msicomp.MsiDirsComponent' }).ROW) { $Directories[$Row.Directory] = $Row }
    $Covered = foreach ($Row in ($Rows | Where-Object { $_.cid -eq 'caphyon.advinst.msicomp.TxtUpdateSetComponent' }).ROW | Where-Object { $_.FileName -eq '*.runtimeconfig.json' }) {
        $Parts = @()
        for ($Key = $Row.Directory; $Key -and $Key -ne 'APPDIR'; $Key = $Directories[$Key].Directory_Parent) {
            if (-not $Directories.ContainsKey($Key)) { throw "Apps.aip has no directory $Key" }
            $Parts = @(($Directories[$Key].DefaultDir -split '\|')[-1]) + $Parts
        }
        $Parts -join '\'
    }
    # Matched by suffix: Get-ChildItem -Recurse returns long names even when FilesDir is the 8.3 path publish-script.bat passes
    $Missing = @($Configs | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique | Where-Object {
        $Dir = $_
        -not @($Covered | Where-Object { $Dir.EndsWith('\' + $_, [StringComparison]::OrdinalIgnoreCase) }).Count
    })
    if ($Missing) { throw "Apps.aip has no runtimeconfig TxtUpdate row for: $($Missing -join ', ')" }
    Write-Host "Apps.aip replaces {APPDIR} in all $(@($Covered).Count) service folders"
}
exit 0
