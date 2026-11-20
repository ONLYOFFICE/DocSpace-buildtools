# Silently installs an Advanced Installer EXE (Prerequisites or Apps), waits for it and reports the result; exit 0 on success.
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$LogDir,
    [int]$TimeoutMinutes = 90,
    [string]$RegistryKey = 'HKLM:\Software\Ascensio System SIA\ONLYOFFICE Apps',
    [string]$SampleCommandLines,           # record process command lines during the install into this file (outside the uploaded folders)
    [Parameter(ValueFromRemainingArguments)][string[]]$Properties = @()
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$name = Split-Path $Path -Leaf
$exeLog = Join-Path $LogDir "$name.exe.log"
$msiLog = Join-Path $LogDir "$name.msi.log"
$resultFile = Join-Path $LogDir "$name.result.txt"
# Logs of an earlier run of the same EXE would fool the error dialog detection and the failure report
Remove-Item -Path $exeLog, $msiLog, $resultFile -Force -ErrorAction SilentlyContinue

# Bootstrapper options (/exenoui, /exelog) must come before the MSI options, otherwise the EXE stops on an error dialog
$arguments = @('/exenoui', '/exelog', "`"$exeLog`"", '/qn', '/norestart', '/L*V', "`"$msiLog`"") + $Properties
Clear-ConflictingProcessEnv
$started = Get-Date
"started: $(Get-Date -Format s)  args: $($arguments -join ' ')" | Set-Content -Path $resultFile -Encoding UTF8
Write-Host "Installing $name"

# Short-lived processes such as msiexec and the Docs setup are caught by sampling, so leaked secrets show up in the checklist
$sampler = $null
if ($SampleCommandLines) {
    New-Item -ItemType Directory -Force -Path (Split-Path $SampleCommandLines) | Out-Null
    $samplerStop = "$SampleCommandLines.stop"
    Remove-Item -Path $SampleCommandLines, $samplerStop -Force -ErrorAction SilentlyContinue
    $shell = (Get-Process -Id $PID).Path
    $sampler = Start-Process -FilePath $shell -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass',
        '-File', "`"$(Join-Path $PSScriptRoot 'cmdline-sampler.ps1')`"", '-Out', "`"$SampleCommandLines`"", '-StopFile', "`"$samplerStop`""
}

# The pwsh module path makes Windows PowerShell 5.1 in the Docs setup load PowerShell 7 modules (Get-Acl fails), so the installer gets the machine one
$pwshModulePath = $env:PSModulePath
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
# No -Wait: it also waits for child processes, and services started by the installer (epmd.exe) never exit
try { $process = Start-Process -FilePath $Path -ArgumentList $arguments -PassThru }
finally { $env:PSModulePath = $pwshModulePath }
# Reading the handle now keeps ExitCode available after the process exits
$null = $process.Handle
$lastReport = $started
$outcome = 'exited'
while (-not $process.WaitForExit(30000)) {
    $elapsed = (Get-Date) - $started
    if ($elapsed.TotalMinutes -ge $TimeoutMinutes) {
        $outcome = 'timeout'
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        break
    }
    # A bootstrapper that rejects its command line shows an "Error" window and waits forever, even with /exenoui
    $process.Refresh()
    if ($elapsed.TotalMinutes -ge 2 -and -not (Test-Path $exeLog) -and -not (Test-Path $msiLog) -and $process.MainWindowTitle -eq 'Error') {
        $outcome = 'bootstrapper error dialog'
        & taskkill.exe /PID $process.Id /T /F | Out-Null
        break
    }
    if (((Get-Date) - $lastReport).TotalMinutes -ge 5) {
        $lastReport = Get-Date
        $lastAction = if (Test-Path $msiLog) {
            Get-Content -Path $msiLog -Tail 400 -ErrorAction SilentlyContinue | Select-String -Pattern 'Action start [\d:]+: (.+)\.$' |
                Select-Object -Last 1 | ForEach-Object { $_.Matches[0].Groups[1].Value }
        }
        $stage = if ($lastAction) { $lastAction } elseif (Test-Path $msiLog) { 'no action start in the last lines of the MSI log' } else { 'no MSI log yet (bootstrapper stage)' }
        Write-Host ("  {0:N0} min, last MSI action: {1}" -f $elapsed.TotalMinutes, $stage)
    }
}

if ($sampler) {
    Set-Content -Path $samplerStop -Value 'stop'
    if (-not $sampler.WaitForExit(60000)) { Stop-Process -Id $sampler.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item -Path $samplerStop -Force -ErrorAction SilentlyContinue
    $sampledCount = if (Test-Path $SampleCommandLines) { @(Get-Content -Path $SampleCommandLines).Count } else { 0 }
    Write-Host "Sampled $sampledCount distinct command lines during the install"
}

$exitCode = if ($outcome -eq 'exited') { $process.ExitCode } else { -1 }
$meaning = switch ($exitCode) {
    0 { 'success' } 3010 { 'success, reboot required' } 1641 { 'success, reboot initiated' } 1602 { 'cancelled' }
    1603 { 'fatal error' } 1618 { 'another installation is running' } -1 { $outcome } default { 'see the logs' } }
$minutes = ((Get-Date) - $started).TotalMinutes
$report = New-Object System.Collections.Generic.List[string]
$report.Add(("exit code: {0} ({1}) after {2:N1} min" -f $exitCode, $meaning, $minutes))

# The new installation generated secrets: hide them in the job log before printing anything from the MSI log
$secretValues = Get-AppsSecretValues -RegistryKey $RegistryKey
Register-CiSecretMask $secretValues
if (Test-Path $msiLog) {
    $failures = @(Select-String -Path $msiLog -Pattern 'Return value 3' | Select-Object -First 5)
    foreach ($failure in $failures) {
        # The failed action is on the "Return value 3" line, its cause is usually a few lines above
        $report.Add("failed: $($failure.Line.Trim())")
        Get-Content -Path $msiLog -TotalCount $failure.LineNumber | Select-Object -Last 8 | ForEach-Object { $report.Add("  | $_") }
    }
    Select-String -Path $msiLog -Pattern 'Installation success or error status' | Select-Object -Last 1 | ForEach-Object { $report.Add($_.Line.Trim()) }
} else {
    $report.Add("no MSI log at ${msiLog}: the bootstrapper failed before the MSI started, see $exeLog")
}
$reportText = Protect-CiText -Text ($report -join "`n") -Values $secretValues
Add-Content -Path $resultFile -Value $reportText -Encoding UTF8
Write-Host $reportText

$summaryLine = "- ``$name``: exit code $exitCode ($meaning), {0:N0} min" -f $minutes
Add-CiSummary $summaryLine
if ($exitCode -eq 0) { exit 0 }
if ($exitCode -in 3010, 1641) {
    Write-CiAnnotation warning "$name asks for a reboot (exit code $exitCode); a hosted runner cannot reboot, the test continues without it"
    exit 0
}
Write-CiAnnotation error "$name failed: exit code $exitCode ($meaning); see $(Split-Path $resultFile -Leaf) in the job artifacts"
exit 1
