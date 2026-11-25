# Builds the ONLYOFFICE Apps Windows installers: runs the stages in order and stops at the first failure (exit code 1).
# Examples: build.ps1 (all stages)   build.ps1 -From publish   build.ps1 -Stages download,package   build.ps1 -Stages installer -Editions CE
# Layout, environment variables and what each stage does: install\win\BUILDING.md.
[CmdletBinding()]
param (
    [string[]]$Stages,                  # names below; powershell -File passes "a,b" as one string, so lists are split here
    [string]$From,                      # this stage and all after it
    [string[]]$Editions = @('CE', 'EE', 'DE', 'Prereq')   # stage 'installer' only; 'package' always builds all
)

$ErrorActionPreference = 'Stop'
$Order = 'clean', 'mcp', 'plugins', 'frontend', 'backend', 'publish', 'copy', 'download', 'package'
$Scripts = @{ mcp = '1-mcp.ps1'; plugins = '2-plugins.ps1'; frontend = '3-frontend.ps1'; backend = '4-backend.ps1'; publish = '5-publish.ps1'
    copy = '6-copy-frontend.ps1'; download = '7-download.ps1'; package = '8-package.ps1'; installer = '8-package.ps1' }

function Split-List([string[]]$Values, [string[]]$Allowed, [string]$Name) {
    $items = @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $wrong = @($items | Where-Object { $Allowed -notcontains $_ })
    if ($wrong) { throw "-${Name}: unknown value(s) $($wrong -join ', '); allowed: $($Allowed -join ', ')" }
    return $items
}

# Empties the outputs of the last build; downloads (out\downloads, out\redist) and the installer cache stay
function Clear-Outputs {
    . "$PSScriptRoot\lib\common.ps1"
    foreach ($folder in (Join-Path $Paths.Out 'Files'), (Join-Path $Paths.Out 'OpenResty'), (Join-Path $Paths.Out 'OpenSearch'), (Join-Path $Paths.Out 'OpenSearchStack'),
        $Paths.Publish, $Paths.License, (Join-Path $Paths.Work 'plugins\publish'), (Join-Path $Paths.Work 'publish')) {
        if (Test-Path -LiteralPath $folder) { Get-ChildItem -LiteralPath $folder -Force | Remove-Item -Recurse -Force }
    }
    Remove-Item -Path (Join-Path $Paths.Installer '*.back*.aip') -Force -ErrorAction SilentlyContinue
}

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
    foreach ($stage in $Run) {
        $begin = Get-Date
        Write-Host "==== stage $stage" -ForegroundColor Cyan
        if ($stage -eq 'clean') { Clear-Outputs }
        elseif ($stage -eq 'installer') { & (Join-Path $PSScriptRoot $Scripts[$stage]) -InstallersOnly -Editions $Editions }
        else { & (Join-Path $PSScriptRoot $Scripts[$stage]) }
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
