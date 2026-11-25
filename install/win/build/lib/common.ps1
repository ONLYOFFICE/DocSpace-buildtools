# Shared by the stage scripts (dot-sourced): workspace paths, tools from environment variables, calls that stop the build on failure.
# The repositories sit side by side in the workspace: buildtools, server, client, campaigns, plugins, mcp (and cloudhsm to sign).

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WinDir = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Paths = @{
    Win       = $WinDir
    Build     = Join-Path $WinDir 'build'
    Lib       = Join-Path $WinDir 'build\lib'
    Installer = Join-Path $WinDir 'installer'
    Runtime   = Join-Path $WinDir 'runtime'
    Out       = Join-Path $WinDir 'out'
    Downloads = Join-Path $WinDir 'out\downloads'
    Files     = Join-Path $WinDir 'out\Files'
    Publish   = Join-Path $WinDir 'out\publish'
    License   = Join-Path $WinDir 'out\license'
}
$Paths.BuildTools = Split-Path (Split-Path $WinDir -Parent) -Parent
$Paths.Work = Split-Path $Paths.BuildTools -Parent
# Relative paths of the helpers (cache folder, NuGet.config) are workspace paths, as in the Jenkins job
Set-Location -LiteralPath $Paths.Work

# Path of a tool from an environment variable such as sevenzip or AdvancedInstaller (the Jenkins job sets them with quotes)
function Get-ToolPath([string]$Name) {
    $value = "$([Environment]::GetEnvironmentVariable($Name))".Trim().Trim('"')
    if (-not $value) { throw "Environment variable $Name (path of the tool) is not set" }
    return $value
}

# Runs a program and throws when it fails; stderr stays output, not a PowerShell error
function Invoke-Tool([string]$Exe, [string[]]$Arguments, [string]$What) {
    if (-not $What) { $What = "$(Split-Path $Exe -Leaf) $($Arguments -join ' ')" }
    Write-Host "> $What"
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & $Exe @Arguments; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previous }
    if ($code -ne 0) { throw "$What failed with exit code $code" }
}

# xcopy with the switches the batch scripts used (/S, or /S /E with -Empty, files only with -Flat); exit code 0 means files were copied
function Copy-Tree([string]$Source, [string]$Destination, [switch]$Empty, [switch]$Flat) {
    $switches = if ($Flat) { @('/y', '/b', '/i') } elseif ($Empty) { @('/s', '/e', '/y', '/i') } else { @('/s', '/y', '/b', '/i') }
    Invoke-Tool 'xcopy.exe' (@($Source, $Destination) + $switches + '/q') "copy $Source to $Destination"
}

# Replaces text in a UTF-8 file and keeps its bytes otherwise: a BOM and the line breaks stay as they are
function Update-TextFile([string]$Path, [string]$Pattern, [string]$Replacement, [string]$Target = $Path) {
    $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($Path))
    [IO.File]::WriteAllBytes($Target, [Text.Encoding]::UTF8.GetBytes([regex]::Replace($text, $Pattern, $Replacement)))
}

function New-Folder([string[]]$Path) { foreach ($p in $Path) { New-Item -ItemType Directory -Force -Path $p | Out-Null } }

function Remove-Folder([string[]]$Path) { foreach ($p in $Path) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force } } }

# Every pattern (relative to the workspace) must match a file or folder after a stage
function Assert-Paths([string]$Stage, [string[]]$Patterns) {
    $missing = @($Patterns | Where-Object { -not (Get-ChildItem -Path (Join-Path $Paths.Work $_) -Force -ErrorAction SilentlyContinue) })
    if ($missing) { throw "Stage $Stage did not produce: $($missing -join ', ')" }
    Write-Host "Stage ${Stage}: $($Patterns.Count) expected item(s) present"
}
