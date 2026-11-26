# Downloads an installer with retries (Jenkins login:token from JENKINS_AUTH) and checks its Authenticode signature.
# With -UseJenkinsAuth, Url is an artifact path relative to the appserver.exe job on the host from the JENKINS_HOST secret.
param(
    [Parameter(Mandatory)][string]$Url,
    [Parameter(Mandatory)][string]$Directory,
    [ValidateSet('Required', 'Expected', 'Optional')][string]$Signature = 'Required',
    [switch]$UseJenkinsAuth,
    [string]$EnvName,                      # also export the local path in this variable for the next steps
    [int]$TimeoutMinutes = 40
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking

New-Item -ItemType Directory -Force -Path $Directory | Out-Null
if ($UseJenkinsAuth) {
    if (-not $env:JENKINS_HOST) { Write-CiAnnotation error 'JENKINS_HOST is not set'; exit 1 }
    $Url = "https://$($env:JENKINS_HOST)/job/appserver.exe/$($Url.TrimStart('/'))"
}
$fileName = [IO.Path]::GetFileName(([uri]$Url).AbsolutePath)
$target = Join-Path $Directory $fileName
$curlConfig = Join-Path $Directory "$fileName.curlrc"
$started = Get-Date

# A config file keeps the credentials out of the command line; each attempt resumes the partial file of the previous one
$configLines = @("url = `"$Url`"", "output = `"$($target.Replace('\', '/'))`"", 'fail', 'location', 'silent', 'show-error',
    'continue-at = -', 'connect-timeout = 60', 'speed-limit = 10240', 'speed-time = 120')
if ($UseJenkinsAuth) {
    if (-not $env:JENKINS_AUTH) { Write-CiAnnotation error 'JENKINS_AUTH is not set'; exit 1 }
    $configLines += "user = `"$($env:JENKINS_AUTH)`""
}
Remove-Item -Force $target -ErrorAction SilentlyContinue
[IO.File]::WriteAllLines($curlConfig, $configLines)
$deadline = $started.AddMinutes($TimeoutMinutes)
$attempt = 0
try {
    do {
        $attempt++
        & curl.exe --config $curlConfig --max-time ([int][math]::Max(60, ($deadline - (Get-Date)).TotalSeconds))
        $curlExit = $LASTEXITCODE
        if ($curlExit -eq 0) { break }
        $received = if (Test-Path $target) { (Get-Item $target).Length / 1GB } else { 0 }
        Write-Host ("Attempt {0}: curl exit code {1}, {2:N2} GB on disk; resuming" -f $attempt, $curlExit, $received)
        Start-Sleep -Seconds 15
    } while ($attempt -lt 8 -and (Get-Date) -lt $deadline)
} finally {
    Remove-Item -Force $curlConfig -ErrorAction SilentlyContinue
}
if ($curlExit -ne 0 -or -not (Test-Path $target)) {
    Write-CiAnnotation error "Download of $fileName failed after $attempt attempts (curl exit code $curlExit)"
    exit 1
}
$sizeGB = (Get-Item $target).Length / 1GB
$minutes = ((Get-Date) - $started).TotalMinutes
Write-Host ("Downloaded {0}: {1:N2} GB in {2:N1} min" -f $fileName, $sizeGB, $minutes)

# Released installers must be signed; a Jenkins build is signed only with SignBuild=true
$authenticode = Get-AuthenticodeSignature -FilePath $target
$signer = if ($authenticode.SignerCertificate) { $authenticode.SignerCertificate.GetNameInfo('SimpleName', $false) } else { 'none' }
$timestamp = if ($authenticode.TimeStamperCertificate) { 'timestamped' } else { 'no timestamp' }
$message = "Signature of ${fileName}: $($authenticode.Status), signer $signer, $timestamp"
if ($authenticode.Status -eq 'Valid') { Write-Host $message }
elseif ($Signature -eq 'Required') { Write-CiAnnotation error $message; exit 1 }
elseif ($Signature -eq 'Expected') { Write-CiAnnotation error "$message (the build was made with SignBuild=true)"; exit 1 }
else { Write-CiAnnotation warning "$message (the build was made with SignBuild=false)" }
Add-CiSummary "- ``$fileName``: $([math]::Round($sizeGB, 2)) GB, signature $($authenticode.Status) ($signer)"

$version = (Get-Item $target).VersionInfo.ProductVersion
if ($version) { Write-Host "Product version: $version" }
if ($EnvName) { Set-CiEnv $EnvName $target }
$target
