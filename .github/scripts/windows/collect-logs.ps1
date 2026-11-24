# Copies install logs, check results and product logs into -Out for upload, with every known secret value replaced by ***.
param(
    [Parameter(Mandatory)][string]$Out,
    [string]$WorkDir = $env:WORK_DIR,
    [string]$RegistryKey = 'HKLM:\Software\Ascensio System SIA\ONLYOFFICE Apps',
    [int]$MaxFileMB = 8
)
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking

New-Item -ItemType Directory -Force -Path $Out | Out-Null
$secretValues = Get-AppsSecretValues -RegistryKey $RegistryKey
Register-CiSecretMask $secretValues
$maxBytes = $MaxFileMB * 1MB
$utf8 = New-Object Text.UTF8Encoding($false)

# Text of a log file; UTF-16 without a byte order mark (some installer logs) is detected by its zero bytes
function Read-LogText([string]$Path) {
    # Running services keep their logs open for writing, which ReadAllBytes does not allow
    $stream = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    $buffer = [IO.MemoryStream]::new()
    try { $stream.CopyTo($buffer) } finally { $stream.Dispose() }
    $bytes = $buffer.ToArray()
    $hasBom = $bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
    if (-not $hasBom -and $bytes.Length -ge 4 -and $bytes[1] -eq 0 -and $bytes[3] -eq 0) { return [Text.Encoding]::Unicode.GetString($bytes) }
    $reader = [IO.StreamReader]::new([IO.MemoryStream]::new($bytes), $true)
    try { $reader.ReadToEnd() } finally { $reader.Dispose() }
}

# Copies one text file redacted; a large file keeps its first and last lines, where install failures and summaries are
function Copy-Redacted([IO.FileInfo]$File, [string]$Destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $Destination) | Out-Null
    $text = if ($File.Length -le $maxBytes) { Read-LogText $File.FullName } else {
        $head = Get-Content -Path $File.FullName -TotalCount 20000
        $tail = Get-Content -Path $File.FullName -Tail 60000
        (@($head) + @("... [$([math]::Round($File.Length / 1MB)) MB file truncated by collect-logs.ps1] ...") + @($tail)) -join "`r`n"
    }
    [IO.File]::WriteAllText($Destination, (Protect-CiText -Text $text -Values $secretValues), $utf8)
}

function Copy-Folder([string]$Source, [string]$Target, [string[]]$Include = @('*.log', '*.txt', '*.json', '*.err', '*.out')) {
    if (-not $Source -or -not (Test-Path $Source)) { return }
    $sourceRoot = (Resolve-Path $Source).Path.TrimEnd('\')
    foreach ($file in @(Get-ChildItem -Path $sourceRoot -Recurse -File -Include $Include -ErrorAction SilentlyContinue)) {
        Copy-Redacted $file (Join-Path (Join-Path $Out $Target) $file.FullName.Substring($sourceRoot.Length + 1))
    }
}

# Our own files: installer results and logs, expected.json, checklist and state results, smoke state
Copy-Folder $WorkDir 'ci'

$installation = Get-AppsInstallation
if ($installation.AppDir) { Copy-Folder (Join-Path $installation.AppDir 'Logs') 'apps-logs' }
if ($installation.Docs -and $installation.Docs.InstallLocation) { Copy-Folder (Join-Path $installation.Docs.InstallLocation 'Log') 'docs-logs' }
Copy-Folder 'C:\OpenSearch\logs' 'opensearch-logs' @('*.log')
Copy-Folder 'C:\OpenResty\logs' 'openresty-logs' @('error.log')
# OpenSearch Dashboards and Fluent Bit write their own and their WinSW logs inside the OpenSearchStack folder
Copy-Folder 'C:\OpenSearchStack' 'opensearchstack-logs' @('*.log', '*.err', '*.out')
# The bootstrapper downloads and logs prerequisites in the user temp folder
Copy-Folder $env:TEMP 'temp-installer-logs' @('*Prerequisite*.log', 'MSI*.LOG', 'ONLYOFFICE*.log', 'Setup Log*.txt', 'bitrock_installer*.log', 'install-postgresql.log')

# Service and product inventory, without any configuration values
$inventory = @()
$inventory += Get-Service -Name 'Apps.*', 'Ds*', 'OpenSearch*', 'OpenResty', 'RabbitMQ', 'Redis', 'MySQL*', 'postgresql*' -ErrorAction SilentlyContinue |
    Sort-Object Name | ForEach-Object { "{0,-45} {1,-10} {2}" -f $_.Name, $_.Status, $_.StartType }
$inventory += ''
$inventory += $installation.Entries | Sort-Object DisplayName | ForEach-Object { "{0} | {1}" -f $_.DisplayName, $_.DisplayVersion }
# Services start a bare "java", so the first java.exe on the machine PATH decides which JDK runs Identity
$inventory += ''
$inventory += 'java.exe on the machine PATH, in search order:'
$inventory += [Environment]::GetEnvironmentVariable('PATH', 'Machine').Split(';') | Where-Object { $_ -and (Test-Path (Join-Path $_ 'java.exe')) } | ForEach-Object { "  $_" }
[IO.File]::WriteAllLines((Join-Path $Out 'inventory.txt'), [string[]]$inventory, $utf8)

# Last line of defence: a collected file that still contains a known secret value is replaced by a note, never uploaded
$files = @(Get-ChildItem -Path $Out -Recurse -File)
$withheld = 0
foreach ($file in $files) {
    $collected = [IO.File]::ReadAllText($file.FullName)
    if (@($secretValues | Where-Object { $collected.Contains($_) }).Count) {
        [IO.File]::WriteAllText($file.FullName, "withheld by collect-logs.ps1: the file still contained a secret value after redaction`r`n", $utf8)
        $withheld++
    }
}
if ($withheld) { Write-CiAnnotation warning "collect-logs: $withheld collected files still held a secret value after redaction and were withheld" }
Write-Host ("Collected {0} files, {1:N1} MB, into {2}; {3} secret values redacted" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB), $Out, $secretValues.Count)
exit 0
