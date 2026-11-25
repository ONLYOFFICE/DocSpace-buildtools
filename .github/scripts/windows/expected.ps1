# Reads what a correct Apps installation must contain from install/win of a buildtools checkout and writes expected.json.
# Example: expected.ps1 -BuildTools build-src -Edition CE -Version 4.1.1067 -Out expected.json
param(
    [Parameter(Mandatory)][string]$BuildTools,
    [Parameter(Mandatory)][ValidateSet('CE', 'EE', 'DE')][string]$Edition,
    [string]$Version,                      # BUILD_VERSION.BUILD_NUMBER of the tested installer, e.g. 4.1.1067
    [string]$Commit,                       # buildtools commit; read from git when omitted
    [Parameter(Mandatory)][string]$Out
)
$ErrorActionPreference = 'Stop'
# .NET file calls resolve relative paths against the process folder, not the PowerShell location
$BuildTools = (Resolve-Path -LiteralPath $BuildTools).Path
$installWin = Join-Path $BuildTools 'install\win'
# install/win is split into build, installer and runtime since 4.1; older commits (the released version of an update test) keep everything flat
if (Test-Path -LiteralPath (Join-Path $installWin 'installer\Apps.aip')) {
    $installerDir = Join-Path $installWin 'installer'
    $buildDir = Join-Path $installWin 'build'
    $winswDir = Join-Path $installWin 'runtime\winsw'
} else {
    $installerDir = $buildDir = $installWin
    $winswDir = Join-Path $installWin 'tools'
}
$aipText = [IO.File]::ReadAllText((Join-Path $installerDir 'Apps.aip'))
$prerequisitesText = [IO.File]::ReadAllText((Join-Path $installerDir 'Apps.Prerequisites.aip'))
$utilsText = [IO.File]::ReadAllText((Join-Path $installerDir 'utils.ps1'))
$mysqlRunnerText = [IO.File]::ReadAllText((Join-Path $installerDir 'MySQL Server Installer Runner.iss'))

function Get-AipProperty([string]$Name) {
    $match = [regex]::Match($aipText, "<ROW Property=`"$([regex]::Escape($Name))`" Value=`"([^`"]*)`"")
    if ($match.Success) { $match.Groups[1].Value } else { $null }
}
function Get-FirstMatch([string]$Text, [string]$Pattern, [string]$What) {
    $match = [regex]::Match($Text, $Pattern)
    if (-not $match.Success) { throw "Cannot find $What (pattern $Pattern)" }
    $match.Groups[1].Value
}

# Component versions: build\versions.ps1 since the PowerShell build, the set lines of build-batch.bat before it
$versionsFile = Join-Path $buildDir 'versions.ps1'
$opensearchVersion = if (Test-Path -LiteralPath $versionsFile) {
    Get-FirstMatch ([IO.File]::ReadAllText($versionsFile)) "OpenSearch\s*=\s*'([^']+)'" 'OpenSearch in build\versions.ps1'
} else {
    Get-FirstMatch ([IO.File]::ReadAllText((Join-Path $buildDir 'build-batch.bat'))) 'set "opensearch_version=([^"]+)"' 'opensearch_version in build-batch.bat'
}

if (-not $Commit) {
    # Native stderr must not turn into a terminating error under ErrorActionPreference Stop
    $ErrorActionPreference = 'Continue'
    $Commit = (& git -C $BuildTools rev-parse --short HEAD 2>$null) | Select-Object -First 1
    $ErrorActionPreference = 'Stop'
}

# PRODUCT_NAME holds the CE value and a MultiBuildValue for the EE (ExeBuild) and DE (ExeBuild_1) builds
$productMatch = [regex]::Match($aipText, '<ROW Property="PRODUCT_NAME" Value="([^"]*)" MultiBuildValue="ExeBuild:([^#"]*)#ExeBuild_1:([^"]*)"')
if (-not $productMatch.Success) { throw 'Cannot find PRODUCT_NAME with its MultiBuildValue in Apps.aip' }
$productName = @{ CE = $productMatch.Groups[1].Value; EE = $productMatch.Groups[2].Value; DE = $productMatch.Groups[3].Value }[$Edition]
$environment = @{ CE = 'community'; EE = 'enterprise'; DE = 'developer' }[$Edition]

# Apps services: every ServiceInstall row with the account it runs as (empty StartName means LocalSystem)
$serviceAccounts = [ordered]@{}
foreach ($row in [regex]::Matches($aipText, '<ROW ServiceInstall="ServiceName_([^"]+)"[^>]*>')) {
    $serviceName = Get-AipProperty "ServiceName_$($row.Groups[1].Value)"
    if (-not $serviceName) { throw "Cannot resolve ServiceName_$($row.Groups[1].Value) in Apps.aip" }
    $account = [regex]::Match($row.Value, 'StartName="([^"]*)"')
    $serviceAccounts[$serviceName] = if ($account.Success) { $account.Groups[1].Value } else { 'LocalSystem' }
}
$services = @($serviceAccounts.Keys | Sort-Object)

# WinSW wrappers: Apps.* run from APPDIR\tools, the rest are infrastructure services; the priority is the process priority class
$servicePriorities = [ordered]@{}
$infraServices = foreach ($wrapper in Get-ChildItem (Join-Path $winswDir '*.xml')) {
    $service = ([xml](Get-Content $wrapper.FullName -Raw)).service
    if (-not $service.id) { continue }
    if ($service.priority) { $servicePriorities[$service.id] = "$($service.priority)".Trim() }
    if ($service.id -notlike 'Apps.*') { $service.id }
}
$infraServices = @($infraServices | Sort-Object -Unique)

# Registry values under Software\[Manufacturer]\[ShortProductName]; Name="\" is the key itself
$registryNames = [regex]::Matches($aipText, '<ROW Registry="[^"]*" Root="-1" Key="Software\\\[Manufacturer\]\\\[ShortProductName\]" Name="([^"]+)"') |
    ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -ne '\' } | Sort-Object -Unique
$registryKey = "HKLM:\Software\$(Get-AipProperty 'Manufacturer')\$(Get-AipProperty 'ShortProductName')"

# Prerequisites with their minimal versions, as the Prerequisites EXE ships them
$prerequisites = [regex]::Matches($prerequisitesText, '<ROW PrereqKey="([^"]+)" DisplayName="([^"]+)" VersionMin="([^"]*)" SetupFileUrl="([^"]+)"') |
    ForEach-Object { [ordered]@{ key = $_.Groups[1].Value; name = $_.Groups[2].Value; versionMin = $_.Groups[3].Value; file = Split-Path $_.Groups[4].Value -Leaf } }

# Hardening of the installer (LockSecrets in utils.ps1): ACLs, own database and broker users; $null for a build without it
$hardening = $null
if ($utilsText -match 'function LockSecrets\b') {
    $writableList = Get-FirstMatch $utilsText '\$WritableDirs = ([^\r\n]+)' 'WritableDirs in utils.ps1'
    $hardening = [ordered]@{
        appDirSddl      = (Get-FirstMatch $utilsText '\$ReadOnlySddl = ''([^'']+)''' 'ReadOnlySddl in utils.ps1')
        writableDirs    = @([regex]::Matches($writableList, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
        registryKeySddl = (Get-FirstMatch $utilsText 'SetSecurityDescriptorSddlForm\(''(D:P[^'']*;;;SY\)[^'']*)''\)' 'settings key SDDL in utils.ps1')
        # A fresh install creates <DB_NAME>_user (the name cut to 27 characters) and an own RabbitMQ user
        mysqlAppUser    = ($utilsText -match 'function CreateMySqlApplicationUser\b')
        dbNameMaxLength = [int](Get-FirstMatch $utilsText '\$DbName\.Substring\(0, \[Math\]::Min\((\d+), \$DbName\.Length\)\) \+ ''_user''' 'app user name rule in utils.ps1')
        rabbitMqUser    = (Get-FirstMatch $utilsText 'function RabbitMqConfigure[\s\S]*?\$User = ''([^'']+)''' 'RabbitMQ user in utils.ps1')
        postgresSuper   = ($utilsText -match 'ALTER USER postgres WITH ENCRYPTED PASSWORD')
        lockedLogLine   = 'The settings key and the install directory are restricted.'
    }
}

# Since 4.1 the installer takes the newest versioned Fluent Bit folder, so the expected path holds a wildcard
$fluentBitFixed = [regex]::Match($utilsText, '\$FluentBitDstFolder = "([^"]+)"')
$fluentBitConfDir = if ($fluentBitFixed.Success) { $fluentBitFixed.Groups[1].Value } else {
    $fluentBitRoot = [regex]::Match($utilsText, '\$FluentBitDir = GetNewestVersionedFolder "([^"]+)" "([^"]+)"')
    if (-not $fluentBitRoot.Success) { throw 'Cannot find the Fluent Bit folder in utils.ps1' }
    $fluentBitSubfolder = Get-FirstMatch $utilsText '\$FluentBitDstFolder = Join-Path \$FluentBitDir\.FullName "([^"]+)"' 'Fluent Bit conf subfolder in utils.ps1'
    Join-Path (Join-Path $fluentBitRoot.Groups[1].Value $fluentBitRoot.Groups[2].Value) $fluentBitSubfolder
}

$expected = [ordered]@{
    generatedFrom    = (Resolve-Path $BuildTools).Path
    commit           = $Commit
    edition          = $Edition
    productName      = $productName
    environment      = $environment
    version          = $Version
    upgradeCode      = (Get-AipProperty 'UpgradeCode')
    appPort          = (Get-AipProperty 'APP_PORT')
    docsPort         = (Get-AipProperty 'DOCUMENT_SERVER_PORT')
    registryKey      = $registryKey
    registryValues   = @($registryNames)
    services         = $services
    serviceAccounts  = $serviceAccounts
    servicePriorities = $servicePriorities
    infraServices    = $infraServices
    docsServices     = @('DsDocServiceSvc', 'DsConverterSvc', 'DsProxySvc')
    # Known issues reported as WARN: Files.Worker stops on a RedisTimeout at its first start, Dashboards does not start on a hosted runner
    servicesMayStop  = @('Apps.Files.Worker', 'OpenSearchDashboards')
    mysqlService     = (Get-FirstMatch $mysqlRunnerText '(MySQL\d{2,})' 'MySQL service name in MySQL Server Installer Runner.iss')
    opensearch       = [ordered]@{
        version  = $opensearchVersion
        indexDir = (Get-FirstMatch $utilsText 'Join-Path \$AppDir "(Data\\Index\\v[^"\\]+)\\?"' 'index directory in utils.ps1')
        yml      = 'C:\OpenSearch\config\opensearch.yml'
        jvm      = 'C:\OpenSearch\config\jvm.options'
        heap     = (Get-FirstMatch $utilsText '"-Xms\.\*" "(-Xms\w+)"' 'heap size in utils.ps1')
    }
    fluentBitConfDir = $fluentBitConfDir
    openRestyConfDir = (Get-FirstMatch $utilsText '\$TargetFolder = "([^"]+)"' 'OpenResty conf folder in utils.ps1')
    firewallRules    = @([regex]::Matches($aipText, 'FirewallException="[^"]*"[^>]*DisplayName="([^"]+)"') |
                         ForEach-Object { $_.Groups[1].Value.Replace('[ProductName]', $productName) })
    prerequisites    = @($prerequisites)
    hardening        = $hardening
}

$json = $expected | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding($false)))
Write-Host "expected: $Out (commit $Commit)"
$accounts = ($serviceAccounts.Values | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
Write-Host ("  {0} | {1} services ({2}) | {3} infrastructure services | {4} registry values | OpenSearch {5} | {6} prerequisites | hardening {7}" -f
    $productName, $services.Count, $accounts, $infraServices.Count, @($registryNames).Count, $expected.opensearch.version, @($prerequisites).Count,
    $(if ($hardening) { 'yes' } else { 'no (build without LockSecrets)' }))
# A failed git rev-parse must not leak its exit code into the step result
exit 0
