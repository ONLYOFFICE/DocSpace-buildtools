# Prepares a GitHub-hosted Windows runner for an Apps install: picks folders by free space and removes conflicting software.
# Sets DOWNLOAD_DIR, WORK_DIR, LOG_DIR and PRIVATE_DIR for the following steps. Example: prepare-runner.ps1 -DownloadGB 8 -InstallGB 25
param(
    [int]$DownloadGB = 8,                  # free space needed for the installers that are on disk at the same time
    [int]$InstallGB = 25                   # free space needed on the system drive for prerequisites, Apps, Docs and data
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking

$system = Get-CimInstance Win32_OperatingSystem
$processor = Get-CimInstance Win32_Processor | Select-Object -First 1
Write-Host ("{0} {1}, {2} logical CPUs, RAM {3:N1} GB ({4:N1} GB free)" -f $system.Caption, $system.Version,
    $processor.NumberOfLogicalProcessors, ($system.TotalVisibleMemorySize / 1MB), ($system.FreePhysicalMemory / 1MB))

# ---- disk: installers go to the fixed drive with the most free space, the products always install to the system drive
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [pscustomobject]@{ Drive = $_.DeviceID; FreeGB = [math]::Round($_.FreeSpace / 1GB, 1); SizeGB = [math]::Round($_.Size / 1GB, 1) } })
$drives | Format-Table -AutoSize | Out-String | Write-Host
$systemDrive = $drives | Where-Object Drive -eq $env:SystemDrive
if ($systemDrive.FreeGB -lt $InstallGB) {
    Write-CiAnnotation error "Only $($systemDrive.FreeGB) GB free on $($env:SystemDrive), the install needs about $InstallGB GB"
    exit 1
}
$downloadDrive = $drives | Sort-Object FreeGB -Descending | Select-Object -First 1
$neededOnDownloadDrive = if ($downloadDrive.Drive -eq $env:SystemDrive) { $DownloadGB + $InstallGB } else { $DownloadGB }
if ($downloadDrive.FreeGB -lt $neededOnDownloadDrive) {
    Write-CiAnnotation error "Only $($downloadDrive.FreeGB) GB free on $($downloadDrive.Drive), the installers and the install need about $neededOnDownloadDrive GB"
    exit 1
}
$workRoot = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
Set-CiEnv DOWNLOAD_DIR (Join-Path "$($downloadDrive.Drive)\" 'apps-ci-download')
Set-CiEnv WORK_DIR (Join-Path $workRoot 'apps-ci')
Set-CiEnv LOG_DIR (Join-Path $workRoot 'apps-ci\logs')
# Files that may hold secrets (sampled command lines); collect-logs.ps1 uploads WORK_DIR only, so this folder stays outside it
Set-CiEnv PRIVATE_DIR (Join-Path $workRoot 'apps-ci-private')
foreach ($folder in @($env:DOWNLOAD_DIR, $env:WORK_DIR, $env:LOG_DIR, $env:PRIVATE_DIR)) { New-Item -ItemType Directory -Force -Path $folder | Out-Null }
Write-Host "Installers: $env:DOWNLOAD_DIR; work files: $env:WORK_DIR"

# ---- Defender scanning of multi-gigabyte installers and of every unpacked file slows the install down a lot
try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop; Write-Host 'Defender real-time monitoring disabled' }
catch { Write-Host "Defender real-time monitoring left as is: $($_.Exception.Message)" }

# ---- Windows Update restarted a test VM in the middle of an install once; a hosted runner must not install updates during the job
foreach ($updateService in 'wuauserv', 'UsoSvc') {
    try { Stop-Service -Name $updateService -Force -ErrorAction Stop; Set-Service -Name $updateService -StartupType Disabled -ErrorAction Stop; Write-Host "$updateService stopped and disabled" }
    catch { Write-Host "$updateService left as is: $($_.Exception.Message)" }
}

# ---- image PostgreSQL: the prerequisite search accepts any PostgreSQL >= 14, skips its own and then cannot log in
foreach ($entry in @(Get-UninstallEntries | Where-Object { $_.DisplayName -match '^PostgreSQL \d' })) {
    Write-Host "Removing preinstalled $($entry.DisplayName)"
    Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Stop-Service -Force -ErrorAction SilentlyContinue
    $uninstaller = ($entry.UninstallString -replace '^"([^"]+)".*$', '$1')
    if ($uninstaller -and (Test-Path $uninstaller)) {
        $uninstall = Start-Process -FilePath $uninstaller -ArgumentList '--mode', 'unattended' -Wait -PassThru
        Write-Host "  uninstaller exit code $($uninstall.ExitCode)"
    }
    if ($entry.InstallLocation -and (Test-Path $entry.InstallLocation)) { Remove-Item -Recurse -Force $entry.InstallLocation -ErrorAction SilentlyContinue }
}
foreach ($service in @(Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue)) {
    Write-Host "Deleting leftover service $($service.Name)"
    & sc.exe delete $service.Name | Out-Null
}
foreach ($key in @('HKLM:\SOFTWARE\PostgreSQL Global Development Group', 'HKLM:\SOFTWARE\PostgreSQL',
                   'HKLM:\SOFTWARE\WOW6432Node\PostgreSQL Global Development Group', 'HKLM:\SOFTWARE\WOW6432Node\PostgreSQL')) {
    if (Test-Path $key) { Write-Host "Removing $key"; Remove-Item -Recurse -Force $key }
}

# ---- MySQL of the runner image: it holds port 3306 and its registry keys match the MySQL prerequisite search
foreach ($service in @(Get-Service -Name 'MySQL*' -ErrorAction SilentlyContinue)) {
    Write-Host "Deleting preinstalled MySQL service $($service.Name)"
    Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
    & sc.exe delete $service.Name | Out-Null
}
foreach ($entry in @(Get-UninstallEntries | Where-Object { $_.DisplayName -match '^MySQL Server' -and $_.PSChildName -match '^\{' })) {
    Write-Host "Removing preinstalled $($entry.DisplayName)"
    $uninstall = Start-Process msiexec.exe -ArgumentList '/x', $entry.PSChildName, '/qn', '/norestart' -Wait -PassThru
    Write-Host "  msiexec exit code $($uninstall.ExitCode)"
}
foreach ($key in @('HKLM:\SOFTWARE\MySQL AB', 'HKLM:\SOFTWARE\WOW6432Node\MySQL AB')) {
    if (Test-Path $key) { Write-Host "Removing $key"; Remove-Item -Recurse -Force $key }
}

# ---- machine variables of the image (JDK 8 in JAVA_HOME would be picked up by OpenSearch, PG* by PostgreSQL tools)
foreach ($name in $ConflictingEnvNames) {
    if ([Environment]::GetEnvironmentVariable($name, 'Machine')) {
        Write-Host "Removing machine variable $name"
        [Environment]::SetEnvironmentVariable($name, $null, 'Machine')
    }
}

# ---- ports Apps needs must be free before the install
$ports = 80, 443, 3306, 5432, 5672, 6379, 8083, 9200, 5601
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ports -contains $_.LocalPort })
foreach ($listener in $listeners) {
    $owner = (Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    Write-CiAnnotation warning "Port $($listener.LocalPort) is already in use by $owner (PID $($listener.OwningProcess)) before the install"
}
if (-not $listeners) { Write-Host "Ports $($ports -join ', ') are free" }
