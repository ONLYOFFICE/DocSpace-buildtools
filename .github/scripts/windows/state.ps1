# Saves the installation state before an update (-Save) and compares it after the update (-Compare); secrets kept only as SHA-256.
# Example: state.ps1 -Expected expected.json -Save before.json; state.ps1 -Expected expected.json -Compare before.json -Version 4.1.1067 -Out compare.json
param(
    [Parameter(Mandatory)][string]$Expected,
    [string]$Save,
    [string]$Compare,
    [string]$Version,                      # expected Apps version after the update
    [string]$Out,
    [string]$Title = 'Update state'
)
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking
$expectation = Get-Content -Path $Expected -Raw | ConvertFrom-Json

# Value of a registry or JSON property; $null when the property does not exist
function Get-PropertyValue($Object, [string]$Name) {
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return $null }
    $Object.$Name
}

function Get-InstallState {
    $installation = Get-AppsInstallation
    $apps = $installation.Apps
    $docs = $installation.Docs
    $appDir = $installation.AppDir

    # The current key, or the DocSpace key of releases before the rename; the 32-bit package writes it under WOW6432Node
    $wowKey = $expectation.registryKey -replace '^HKLM:\\Software\\', 'HKLM:\SOFTWARE\WOW6432Node\'
    $keyPath = @($expectation.registryKey, $wowKey, ($expectation.registryKey -replace 'ONLYOFFICE Apps$', 'ONLYOFFICE DocSpace'),
                 ($wowKey -replace 'ONLYOFFICE Apps$', 'ONLYOFFICE DocSpace')) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $keyPath) { $keyPath = $wowKey }
    $registry = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue
    $registryHashes = [ordered]@{}
    foreach ($valueName in $expectation.registryValues) { $registryHashes[$valueName] = Get-Sha256Hex (Get-PropertyValue $registry $valueName) }

    # The installer writes the machine key into appsettings.<environment>.json
    $machineKey = $null
    $identitySecret = $null
    $dataFiles = @()
    if ($appDir) {
        $environmentJson = Read-JsonFile (Join-Path $appDir "config\appsettings.$($expectation.environment).json")
        if ($environmentJson) { $machineKey = $environmentJson.core.machinekey }
        # The Identity service encrypts its data with this key; a new one makes the stored clients unreadable
        $identityXml = Join-Path $appDir 'tools\Identity.Authorization.xml'
        if (Test-Path -LiteralPath $identityXml) {
            $identitySecret = ([xml](Get-Content -LiteralPath $identityXml -Raw)).service.env |
                Where-Object { $_.name -eq 'SPRING_APPLICATION_ENCRYPTION_SECRET' } | Select-Object -First 1 -ExpandProperty value
        }
        # Portal data files, without the search index that OpenSearch rebuilds
        $dataRoot = Join-Path $appDir 'Data'
        if (Test-Path -LiteralPath $dataRoot) {
            $dataFiles = @(Get-ChildItem -LiteralPath $dataRoot -File -Recurse -Force -ErrorAction SilentlyContinue |
                ForEach-Object { $_.FullName.Substring($dataRoot.Length + 1) } | Where-Object { $_ -notlike 'Index\*' } | Sort-Object)
        }
    }

    # The secrets Docs checks editor tokens and logs in to its database with; they must match the Apps values
    $docsJwt = $null
    if ($docs -and $docs.InstallLocation) {
        $localJson = Read-JsonFile (Join-Path $docs.InstallLocation 'config\local.json')
        if ($localJson) { $docsJwt = $localJson.services.CoAuthoring.secret.inbox.string }
    }
    $docsRegistry = Get-ItemProperty $DocsRegistryKey -ErrorAction SilentlyContinue

    $proxyConfig = Join-Path $expectation.openRestyConfDir 'onlyoffice-proxy.conf'
    $sslLines = if (Test-Path $proxyConfig) { Select-String -Path $proxyConfig -Pattern '^\s*ssl_certificate(_key)?\s+(.+);' | ForEach-Object { $_.Line.Trim() } }

    [ordered]@{
        takenAt        = (Get-Date -Format s)
        registryKey    = $keyPath
        apps           = [ordered]@{ name = $apps.DisplayName; version = $apps.DisplayVersion; dir = $appDir }
        docs           = [ordered]@{ name = $docs.DisplayName; edition = (Get-DocsEdition $docs.DisplayName); version = $docs.DisplayVersion; dir = $docs.InstallLocation }
        registry       = $registryHashes
        machineKey     = (Get-Sha256Hex $machineKey)
        identitySecret = (Get-Sha256Hex $identitySecret)
        docsJwt        = (Get-Sha256Hex $docsJwt)
        docsDbPassword = (Get-Sha256Hex (Get-PropertyValue $docsRegistry 'DbPwd'))
        dataFiles      = $dataFiles
        sslLines       = @($sslLines)
        nginxConfs     = @(Get-ChildItem (Join-Path $expectation.openRestyConfDir 'onlyoffice*.conf') -ErrorAction SilentlyContinue |
                           ForEach-Object { [ordered]@{ name = $_.Name; sha256 = (Get-FileHash $_.FullName).Hash } })
        services       = @(Get-Service -Name 'Apps.*' -ErrorAction SilentlyContinue | ForEach-Object { "$($_.Name)=$($_.Status)" })
    }
}

$current = Get-InstallState
if ($Save) {
    $current | ConvertTo-Json -Depth 5 | Set-Content -Path $Save -Encoding UTF8
    Write-Host "saved: $Save  ($($current.apps.name) $($current.apps.version), Docs $($current.docs.version), key $($current.registryKey), $($current.dataFiles.Count) data files)"
    if (-not $current.apps.name) { Write-CiAnnotation error 'No installed Apps to save the state of'; exit 1 }
    exit 0
}
if (-not $Compare) { throw 'pass -Save <file> or -Compare <file>' }

$before = Get-Content -Path $Compare -Raw | ConvertFrom-Json
$results = New-Object System.Collections.ArrayList
function Add-Result([string]$Check, [string]$Status, [string]$Detail = '') { [void]$results.Add([pscustomobject]@{ check = $Check; status = $Status; detail = $Detail }) }

$versionOk = if ($Version) { "$($current.apps.version)" -like "$Version*" } else { $current.apps.version -ne $before.apps.version }
Add-Result 'Apps version updated' $(if ($versionOk) { 'PASS' } else { 'FAIL' }) "$($before.apps.version) -> $($current.apps.version)"
Add-Result 'same edition' $(if ($current.apps.name -eq $before.apps.name) { 'PASS' } else { 'FAIL' }) "$($before.apps.name) -> $($current.apps.name)"
Add-Result 'registry key' $(if ($current.registryKey -like '*ONLYOFFICE Apps') { 'PASS' } else { 'FAIL' }) "$($before.registryKey) -> $($current.registryKey)"

# Absent before: new in this version. Blank before (the " " placeholder or empty) and set now: filled by the update, not lost
$blankHashes = @((Get-Sha256Hex ' '), (Get-Sha256Hex ''))
$changed = @(); $lost = @(); $filled = @(); $added = @()
foreach ($valueName in $expectation.registryValues) {
    $oldHash = $before.registry.$valueName
    $newHash = $current.registry.$valueName
    if ($null -eq $oldHash) { if ($null -ne $newHash) { $added += $valueName }; continue }
    if ($null -eq $newHash) { $lost += $valueName }
    elseif ($oldHash -ne $newHash) { if ($blankHashes -contains $oldHash) { $filled += $valueName } else { $changed += $valueName } }
}
$status = if ($lost -or $changed) { 'FAIL' } elseif ($filled) { 'WARN' } else { 'PASS' }
Add-Result 'registry values kept' $status "lost: $($lost -join ',') changed: $($changed -join ',') filled (blank before): $($filled -join ',') new: $($added -join ',')"

$machineKeyStatus, $machineKeyDetail = if (-not $before.machineKey) { 'WARN', 'no machine key before' }
    elseif ($before.machineKey -eq $current.machineKey) { 'PASS', '' }
    elseif ($blankHashes -contains $before.machineKey) { 'FAIL', 'blank before, replaced by the update: passwords and data protected with the blank key no longer open' }
    elseif (-not $current.machineKey -or $blankHashes -contains $current.machineKey) { 'FAIL', 'set before, blank now' }
    else { 'FAIL', 'changed: data encrypted with the old key will not open' }
Add-Result 'core.machinekey kept' $machineKeyStatus $machineKeyDetail

$identityStatus = if (-not $before.identitySecret) { 'INFO' } elseif ($before.identitySecret -eq $current.identitySecret) { 'PASS' } else { 'FAIL' }
Add-Result 'Identity encryption key kept' $identityStatus $(if ($identityStatus -eq 'FAIL') { 'changed: the stored Identity clients will not open' } elseif ($identityStatus -eq 'INFO') { 'no key before' })

# Apps signs editor tokens with DOCUMENT_SERVER_JWT_SECRET, Docs checks them with its local.json secret
$appsJwt = $current.registry.DOCUMENT_SERVER_JWT_SECRET
if ($current.docsJwt) {
    $same = $appsJwt -eq $current.docsJwt
    $detail = if ($same) { '' } elseif ($blankHashes -contains $appsJwt) { 'Apps value blank, Docs has a secret: editors will not open' } else { 'different secrets: editors will not open' }
    Add-Result 'Apps and Docs JWT match' $(if ($same) { 'PASS' } else { 'FAIL' }) $detail
}
if ($before.docsDbPassword) {
    Add-Result 'Docs DbPwd kept' $(if ($before.docsDbPassword -eq $current.docsDbPassword) { 'PASS' } else { 'FAIL' })
}

Add-Result 'Docs edition kept' $(if ($current.docs.edition -eq $before.docs.edition) { 'PASS' } else { 'FAIL' }) "$($before.docs.edition) -> $($current.docs.edition)"
Add-Result 'Docs version' 'INFO' "$($before.docs.version) -> $($current.docs.version) (not reinstalled when the installed version >= DS_VERSION)"

# The smoke verify phase checks the portal data through the API; this catches files lost on disk
$lostFiles = @($before.dataFiles | Where-Object { $current.dataFiles -notcontains $_ })
Add-Result 'Data files kept' $(if ($lostFiles) { 'WARN' } else { 'PASS' }) "$(@($before.dataFiles).Count) before, $(@($current.dataFiles).Count) now; lost: $(($lostFiles | Select-Object -First 5) -join ', ')"

$sslBefore = @($before.sslLines | Where-Object { $_ })
$sslNow = @($current.sslLines | Where-Object { $_ })
$sslSame = ($sslBefore -join '|') -eq ($sslNow -join '|')
Add-Result 'SSL certificate kept' $(if ($sslSame) { 'PASS' } else { 'FAIL' }) $(if ($sslBefore.Count) { 'had SSL' } else { 'no SSL before' })

$changedConfs = @($before.nginxConfs | Where-Object {
    $old = $_; -not ($current.nginxConfs | Where-Object { $_.name -eq $old.name -and $_.sha256 -eq $old.sha256 }) } | ForEach-Object name)
Add-Result 'nginx confs' 'INFO' $(if ($changedConfs) { 'changed: ' + ($changedConfs -join ', ') } else { 'unchanged' })

$servicesNow = @($current.services | Where-Object { $_ })
$down = @($servicesNow | Where-Object { $_ -notlike '*=Running' })
$knownDown = @($down | Where-Object { @($expectation.servicesMayStop) -contains ($_ -replace '=.*$', '') })
$status = if (-not $servicesNow.Count -or $down.Count -gt $knownDown.Count) { 'FAIL' } elseif ($knownDown) { 'WARN' } else { 'PASS' }
Add-Result 'Apps services running' $status $(if ($servicesNow.Count) { $down -join ', ' } else { 'no Apps.* services' })

exit (Complete-CiResults -Results $results -Title $Title -Out $Out)
