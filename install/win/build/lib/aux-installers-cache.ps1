# Reuses the OpenResty, OpenSearch and OpenSearchStack installers between builds when none of their inputs changed.
# Restore exits 0 when the cached package was put into publish, 1 when the project has to be built; Save stores the built package.
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][ValidateSet('Restore', 'Save')][string]$Action,
    [Parameter(Mandatory = $true)][string]$Project,
    [Parameter(Mandatory = $true)][string]$Package,
    [Parameter(Mandatory = $true)][string[]]$Inputs,
    [string]$Version = '',
    [string]$CacheDir = $env:APPS_WIN_BUILD_CACHE
)

$ErrorActionPreference = 'Stop'
# powershell -File passes "a,b" as one string
$Inputs = @($Inputs | ForEach-Object { $_ -split ',' } | Where-Object { $_ })

# Bump when the key layout changes, so old entries are never reused.
$KeyFormat = '1'
# The projects are in install\win\installer, their inputs and packages in install\win\out
$WinDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$InstallerDir = Join-Path $WinDir 'installer'
$OutDir = Join-Path $WinDir 'out'
$PublishDir = Join-Path $OutDir 'publish'
if (-not $CacheDir) { $CacheDir = Join-Path (Get-Location) 'win-build-cache' }
$ProjectCache = Join-Path $CacheDir $Project
$KeyFile = Join-Path $CacheDir "$Project.pending-key"

function Get-InputsKey {
    $Lines = New-Object System.Collections.Generic.List[string]
    $Lines.Add("format=$KeyFormat")
    $Lines.Add("project=$Project")
    $Lines.Add("package=$Package")
    $Lines.Add("version=$Version")
    $Lines.Add("sign=$env:SignBuild")
    $Installer = ($env:AdvancedInstaller -replace '"', '').Trim()
    $InstallerVersion = if ($Installer -and (Test-Path -LiteralPath $Installer)) { (Get-Item -LiteralPath $Installer).VersionInfo.FileVersion } else { 'unknown' }
    $Lines.Add("advancedinstaller=$InstallerVersion")
    $Lines.Add("aip=" + (Get-FileHash -LiteralPath (Join-Path $InstallerDir "$Project.aip") -Algorithm SHA256).Hash)
    foreach ($InputName in $Inputs) {
        $InputPath = Join-Path $OutDir $InputName
        if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input $InputPath does not exist" }
        $Root = (Resolve-Path -LiteralPath $InputPath).ProviderPath.TrimEnd('\')
        $Files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object { $_.FullName.Substring($Root.Length).ToLowerInvariant() }
        foreach ($File in $Files) {
            $Relative = $InputName + $File.FullName.Substring($Root.Length)
            $Lines.Add($Relative.ToLowerInvariant() + '|' + (Get-FileHash -LiteralPath $File.FullName -Algorithm SHA256).Hash)
        }
    }
    $Bytes = [Text.Encoding]::UTF8.GetBytes([string]::Join("`n", $Lines))
    $Sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($Sha.ComputeHash($Bytes)) -replace '-', '').Substring(0, 32) }
    finally { $Sha.Dispose() }
}

try {
    if ($Action -eq 'Restore') {
        Remove-Item -LiteralPath $KeyFile -Force -ErrorAction SilentlyContinue
        $Key = Get-InputsKey
        New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null
        Set-Content -LiteralPath $KeyFile -Value $Key -Encoding Ascii
        $Cached = Join-Path (Join-Path $ProjectCache $Key) $Package
        if (-not (Test-Path -LiteralPath $Cached)) {
            Write-Host "Cache miss for $Project (key $Key): building it"
            exit 1
        }
        New-Item -ItemType Directory -Force -Path $PublishDir | Out-Null
        Copy-Item -LiteralPath $Cached -Destination (Join-Path $PublishDir $Package) -Force
        Write-Host "Cache hit for $Project (key $Key): reused $Package"
        exit 0
    }

    # Save: the key was computed by Restore before the project was edited and built.
    if (-not (Test-Path -LiteralPath $KeyFile)) { throw "No key for $Project, Restore did not run" }
    $Key = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
    $Built = Join-Path $PublishDir $Package
    if (-not (Test-Path -LiteralPath $Built)) { throw "$Built was not built" }
    $Target = Join-Path $ProjectCache $Key
    $Temp = "$Target.tmp"
    Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $Temp | Out-Null
    Copy-Item -LiteralPath $Built -Destination (Join-Path $Temp $Package) -Force
    # Only the newest entry of a project is kept, so the cache does not grow with every version.
    Get-ChildItem -LiteralPath $ProjectCache -Directory | Where-Object { $_.FullName -ne $Temp } | Remove-Item -Recurse -Force
    Rename-Item -LiteralPath $Temp -NewName (Split-Path $Target -Leaf)
    Write-Host "Cached $Package for $Project (key $Key)"
    exit 0
}
catch {
    # A cache failure never fails the build: Restore falls back to building, Save only warns.
    Write-Host "WARNING: installer cache ${Action} for ${Project} failed: $($_.Exception.Message)"
    exit 1
}
