# Stage 2: builds every docspace-plugins plugin and unpacks its plugin.zip into plugins\publish\<package name>.
. "$PSScriptRoot\lib\common.ps1"

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
