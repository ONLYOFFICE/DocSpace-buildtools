# Waits until the Apps services run, the portal answers and Docs passes its healthcheck; exit 1 on timeout.
param(
    [Parameter(Mandatory)][string]$Expected,
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking
$expectation = Get-Content -Path $Expected -Raw | ConvertFrom-Json

$registry = Get-ItemProperty (Resolve-AppsRegistryKey $expectation.registryKey) -ErrorAction SilentlyContinue
$docsPort = if ($registry -and $registry.DOCUMENT_SERVER_PORT) { $registry.DOCUMENT_SERVER_PORT } else { $expectation.docsPort }
# Services with a known start problem do not hold the wait; the checklist reports them as WARN
$mayStop = @($expectation.servicesMayStop)
$serviceNames = @(@($expectation.services) + @($expectation.infraServices) + @($expectation.docsServices) | Where-Object { $mayStop -notcontains $_ })

function Get-HttpStatus([string]$Url) {
    try { (Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 5).StatusCode } catch {
        if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { 'no answer' } }
}

$started = Get-Date
$deadline = $started.AddMinutes($TimeoutMinutes)
do {
    $notRunning = @($serviceNames | Where-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status -ne 'Running' })
    $portal = Get-HttpStatus "http://localhost:$($expectation.appPort)/"
    $settings = Get-HttpStatus "http://localhost:$($expectation.appPort)/api/2.0/settings"
    $health = try { (Invoke-WebRequest -Uri "http://localhost:$docsPort/healthcheck" -UseBasicParsing -TimeoutSec 20 -MaximumRedirection 0).Content.Trim() } catch { 'no answer' }
    # Anything but the short answer of Docs (a proxy page, an error page) is shown cut, so it cannot flood the log
    if ($health.Length -gt 40) { $health = $health.Substring(0, 40).Replace("`r", ' ').Replace("`n", ' ') + '...' }
    $ready = (-not $notRunning) -and $portal -eq 200 -and $settings -eq 200 -and $health -eq 'true'
    $knownDown = @($mayStop | Where-Object { (Get-Service -Name $_ -ErrorAction SilentlyContinue).Status -ne 'Running' })
    $state = "services not running: $(if ($notRunning) { $notRunning -join ', ' } else { 'none' }) (known: $(if ($knownDown) { $knownDown -join ', ' } else { 'none' })); portal $portal; settings API $settings; Docs healthcheck $health"
    Write-Host ("{0:N1} min: {1}" -f ((Get-Date) - $started).TotalMinutes, $state)
    if ($ready) { break }
    Start-Sleep -Seconds 30
} while ((Get-Date) -lt $deadline)

if ($ready) {
    Write-Host ("Apps is ready after {0:N1} min" -f ((Get-Date) - $started).TotalMinutes)
    exit 0
}
Write-CiAnnotation warning "Apps is not ready after $TimeoutMinutes min: $state"
exit 1
