# Checks an installed Apps against expected.json: PASS/WARN/FAIL table, JSON in -Out, exit code = number of FAIL; secrets never printed.
# Example: checklist.ps1 -Expected expected.json -Mode Fresh -MsiLog Apps.exe.msi.log -CommandLines cmdlines.txt -Out checklist.json
param(
    [Parameter(Mandatory)][string]$Expected,
    [ValidateSet('Fresh', 'Update')][string]$Mode = 'Fresh',
    [string]$MsiLog,                       # MSI log of the Apps install, for failed actions and migrations
    [string]$CommandLines,                 # command lines sampled during the Apps install; may hold secrets, so it is deleted after the check
    [string]$StateBefore,                  # state.ps1 -Save file of the released version, so blank keys it already had are not blamed on the update
    [Parameter(Mandatory)][string]$Out,
    [string]$Title = 'Install checklist'
)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSScriptRoot 'OoWinCi.psm1') -Force -DisableNameChecking
$expectation = Get-Content -Path $Expected -Raw | ConvertFrom-Json
$hardening = $expectation.hardening
$results = New-Object System.Collections.ArrayList
$mayStop = @($expectation.servicesMayStop)

function Add-Result([string]$Id, [string]$Check, [string]$Status, [string]$Detail = '') {
    [void]$results.Add([pscustomobject]@{ id = $Id; check = $Check; status = $Status; detail = $Detail })
}
# Services that are known to stop (servicesMayStop) give WARN instead of FAIL
function Test-Services([string]$Id, [string[]]$Names, [switch]$Automatic) {
    $problems = @(); $known = @()
    foreach ($serviceName in $Names) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) { $problems += "$serviceName missing"; continue }
        if ($Automatic -and $service.StartType -ne 'Automatic') { $problems += "$serviceName start=$($service.StartType)" }
        if ($service.Status -ne 'Running') {
            if ($mayStop -contains $serviceName) { $known += "$serviceName $($service.Status) (known issue)" } else { $problems += "$serviceName $($service.Status)" }
        }
    }
    $status = if ($problems) { 'FAIL' } elseif ($known) { 'WARN' } else { 'PASS' }
    $detail = if ($problems -or $known) { (@($problems) + @($known)) -join '; ' } else { 'all Running' }
    Add-Result $Id "services: $($Names.Count)" $status $detail
}
function Get-TrimmedValue($Object, [string]$Name) {
    if ($null -eq $Object -or -not $Object.PSObject.Properties[$Name]) { return '' }
    "$($Object.$Name)".Trim()
}
# Allow rules of a file system or registry ACL, inherit-only entries left out
function Get-EffectiveRules($Acl) {
    @($Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object {
        $_.AccessControlType -eq 'Allow' -and -not ($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) })
}
function Get-SidMask([object[]]$Rules, [string]$Sid) {
    $mask = 0
    foreach ($rule in $Rules) {
        if ($rule.IdentityReference.Value -ne $Sid) { continue }
        $rights = if ($rule.PSObject.Properties['FileSystemRights']) { $rule.FileSystemRights } else { $rule.RegistryRights }
        $mask = $mask -bor [int]$rights
    }
    $mask
}
function Format-Rules([object[]]$Rules) {
    ($Rules | ForEach-Object {
        $rights = if ($_.PSObject.Properties['FileSystemRights']) { $_.FileSystemRights } else { $_.RegistryRights }
        '{0}:{1}{2}' -f $_.IdentityReference.Value, $rights, $(if ($_.IsInherited) { ':inherited' } else { '' }) }) -join '; '
}

# ---- database and broker clients; passwords go through a restricted file or the environment, never a command line
$mysqlExe = Get-ChildItem 'C:\Program Files\MySQL\MySQL Server*\bin\mysql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
$psqlExe = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\psql.exe' -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
function Invoke-MySqlQuery([string]$User, [string]$Password, [string]$Sql, [string]$Port = '3306') {
    if (-not $mysqlExe) { return [pscustomobject]@{ Code = -1; Output = 'mysql.exe not found' } }
    $directory = New-RestrictedTempDir 'ci-mysql-'
    try {
        $optionFile = Join-Path $directory 'client.cnf'
        [IO.File]::WriteAllText($optionFile, "[client]`r`nuser=`"$User`"`r`npassword=`"$Password`"`r`nhost=127.0.0.1`r`nport=$Port`r`n")
        $output = & $mysqlExe "--defaults-extra-file=$optionFile" -N -B -e $Sql 2>&1
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($output) | ForEach-Object { "$_" }) -join ' ').Trim() }
    } finally { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue }
}
function Invoke-PsqlQuery([string]$User, [string]$Password, [string]$Database, [string]$Sql, [string]$Port = '5432') {
    if (-not $psqlExe) { return [pscustomobject]@{ Code = -1; Output = 'psql.exe not found' } }
    $env:PGPASSWORD = $Password
    try {
        $output = & $psqlExe -h 127.0.0.1 -p $Port -U $User -d $Database -w -t -A -c $Sql 2>&1
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = ((@($output) | ForEach-Object { "$_" }) -join ' ').Trim() }
    } finally { Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }
}
# rabbitmqctl needs the cookie of the broker service, so it runs with a private home that holds a copy of it
function Get-RabbitMqUsers {
    $rabbitCtl = Get-ChildItem "$env:ProgramFiles\RabbitMQ Server\rabbitmq_server-*\sbin\rabbitmqctl.bat" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    $cookie = "$env:SystemRoot\System32\config\systemprofile\.erlang.cookie"
    if (-not $rabbitCtl -or -not (Test-Path -LiteralPath $cookie)) { return $null }
    $ctlHome = New-RestrictedTempDir 'ci-rabbitmqctl-'
    try {
        Copy-Item -LiteralPath $cookie -Destination (Join-Path $ctlHome '.erlang.cookie')
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "$env:SystemRoot\System32\cmd.exe"
        $startInfo.Arguments = "/c `"`"$rabbitCtl`" list_users -q`""
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.EnvironmentVariables['USERPROFILE'] = $ctlHome
        $startInfo.EnvironmentVariables['HOMEDRIVE'] = Split-Path -Qualifier $ctlHome
        $startInfo.EnvironmentVariables['HOMEPATH'] = Split-Path -NoQualifier $ctlHome
        if (-not $env:ERLANG_HOME) { $startInfo.EnvironmentVariables['ERLANG_HOME'] = [Environment]::GetEnvironmentVariable('ERLANG_HOME', 'Machine') }
        $process = [System.Diagnostics.Process]::Start($startInfo)
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(120000)) { $process.Kill(); return 'rabbitmqctl did not finish in 2 minutes' }
        ($stdout.Result + ' ' + $stderr.Result).Trim()
    } finally { Remove-Item -LiteralPath $ctlHome -Recurse -Force -ErrorAction SilentlyContinue }
}

$installation = Get-AppsInstallation
$entries = $installation.Entries
$apps = $installation.Apps
$docs = $installation.Docs

# ---- 0. product
if (-not $apps) { Add-Result '0' 'Apps is installed' 'FAIL' 'no ONLYOFFICE Apps* entry in Uninstall' }
else {
    $status = if ($apps.DisplayName -ne $expectation.productName) { 'FAIL' }
              elseif ($expectation.version -and $apps.DisplayVersion -notlike "$($expectation.version)*") { 'FAIL' } else { 'PASS' }
    Add-Result '0' 'Apps edition and version' $status "$($apps.DisplayName) $($apps.DisplayVersion) (expected $($expectation.productName) $($expectation.version))"
}
$appDir = $installation.AppDir
Add-Result '0' 'APPDIR' $(if ($appDir -and (Test-Path $appDir)) { 'PASS' } else { 'FAIL' }) "$appDir"
# Without APPDIR the checks below still run and fail on their own instead of throwing on Join-Path
if (-not $appDir) { $appDir = 'C:\APPDIR-not-found\' }

$registryKey = Resolve-AppsRegistryKey $expectation.registryKey
$registry = Get-ItemProperty $registryKey -ErrorAction SilentlyContinue
$docsRegistry = Get-ItemProperty $DocsRegistryKey -ErrorAction SilentlyContinue
$docsDir = if ($docs) { "$($docs.InstallLocation)".TrimEnd('\') } else { '' }
$docsLocalJson = if ($docsDir) { Read-JsonFile (Join-Path $docsDir 'config\local.json') } else { $null }

# ---- 1. prerequisites
$prerequisitePatterns = [ordered]@{
    'MySQL Server'         = 'MySQL Server'
    'MySQL Connector/ODBC' = 'MySQL Connector/ODBC'
    'PostgreSQL'           = 'PostgreSQL'
    'RabbitMQ'             = 'RabbitMQ'
    'Erlang'               = 'Erlang'
    'Redis'                = '^Redis'
    '.NET Runtime 10'      = 'Microsoft \.NET Runtime - 10\.'
    'ASP.NET Core 10'      = 'ASP\.NET Core.* 10\.'
    'JDK'                  = 'OpenJDK|Java\(TM\) SE Development Kit|JDK'
    'Node.js'              = '^Node\.js'
    'FFmpeg'               = 'FFmpeg'
    'OpenSSL'              = 'OpenSSL'
    'Certbot'              = 'Certbot'
    'OpenSearch'           = '^OpenSearch'
    'OpenResty'            = '^OpenResty'
}
$missing = @(); $found = @()
foreach ($label in $prerequisitePatterns.Keys) {
    $hit = $entries | Where-Object { $_.DisplayName -match $prerequisitePatterns[$label] } | Select-Object -First 1
    if ($hit) { $found += "$label $($hit.DisplayVersion)" } else { $missing += $label }
}
Add-Result '1' 'prerequisites installed' $(if ($missing) { 'FAIL' } else { 'PASS' }) $(if ($missing) { 'missing: ' + ($missing -join ', ') } else { $found -join '; ' })
Test-Services '1' @($expectation.mysqlService)
# Prefer a running PostgreSQL service when several exist
$postgres = Get-Service -Name 'postgresql*' -ErrorAction SilentlyContinue | Sort-Object { $_.Status -ne 'Running' } | Select-Object -First 1
Add-Result '1' 'PostgreSQL service' $(if ($postgres -and $postgres.Status -eq 'Running') { 'PASS' } else { 'FAIL' }) "$($postgres.Name) $($postgres.Status)"
Test-Services '1' @('RabbitMQ', 'Redis')

# ---- 2-3. services
Test-Services '2' @($expectation.services) -Automatic
Test-Services '3' @($expectation.infraServices)

# ---- 4. Docs
if (-not $docs) { Add-Result '4' 'Docs installed' 'FAIL' 'no ONLYOFFICE DocumentServer_is1' }
else {
    $docsEdition = Get-DocsEdition $docs.DisplayName
    Add-Result '4' 'Docs edition matches Apps' $(if ($docsEdition -eq $expectation.edition) { 'PASS' } else { 'FAIL' }) "$($docs.DisplayName) $($docs.DisplayVersion) -> $docsEdition"
    $wantedDocsDir = Join-Path (Split-Path $appDir.TrimEnd('\')) 'DocumentServer'
    Add-Result '4' 'Docs folder next to Apps' $(if ($docsDir -eq $wantedDocsDir) { 'PASS' } else { 'WARN' }) "$docsDir (expected $wantedDocsDir; C:\DocumentServer is a known issue of the silent path: the bootstrapper runs the Docs prerequisite before the MSI sets APPDIR)"
    Test-Services '4' @($expectation.docsServices)
    $docsPort = if ($registry -and $registry.DOCUMENT_SERVER_PORT) { $registry.DOCUMENT_SERVER_PORT } else { $expectation.docsPort }
    $dsConf = Join-Path $docsDir 'nginx\conf\ds.conf'
    $listen = Select-String -Path $dsConf -Pattern '^\s*listen\s+(?:0\.0\.0\.0|\[::\]):(\d+)' -ErrorAction SilentlyContinue | Select-Object -First 1
    $listenPort = if ($listen) { $listen.Matches[0].Groups[1].Value } else { 'not found' }
    Add-Result '4' 'ds.conf listen = DOCUMENT_SERVER_PORT' $(if ($listenPort -eq $docsPort) { 'PASS' } else { 'FAIL' }) "listen $listenPort, expected $docsPort"
    $health = try { (Invoke-WebRequest "http://localhost:$docsPort/healthcheck" -UseBasicParsing -TimeoutSec 20).Content.Trim() } catch { $_.Exception.Message }
    Add-Result '4' 'Docs /healthcheck' $(if ($health -eq 'true') { 'PASS' } else { 'FAIL' }) "$health"
}

# ---- 5. JWT: Apps signs editor tokens with DOCUMENT_SERVER_JWT_SECRET, Docs checks them with its own copy
$jwt = Get-TrimmedValue $registry 'DOCUMENT_SERVER_JWT_SECRET'
if (-not $jwt) { Add-Result '5' 'JWT secret' 'FAIL' "DOCUMENT_SERVER_JWT_SECRET blank in $registryKey" }
else {
    $inAppsConfig = Select-String -Path (Join-Path $appDir 'config\*.json') -SimpleMatch -Pattern $jwt -List -ErrorAction SilentlyContinue
    $localJsonJwt = if ($docsLocalJson) { "$($docsLocalJson.services.CoAuthoring.secret.inbox.string)".Trim() } else { '' }
    $docsRegistryJwt = Get-TrimmedValue $docsRegistry 'JwtSecret'
    $appsState = if ($inAppsConfig) { ($inAppsConfig.Filename | Select-Object -Unique) -join ',' } else { 'not found' }
    Add-Result '5' 'JWT secret in the Apps config' $(if ($inAppsConfig) { 'PASS' } else { 'FAIL' }) "Apps config: $appsState; registry length $($jwt.Length)"
    $state = if (-not $docs) { 'no Docs' } elseif (-not $localJsonJwt) { 'blank' } elseif ($localJsonJwt -eq $jwt) { 'same' } else { 'DIFFERENT' }
    Add-Result '5' 'Docs local.json inbox secret = Apps secret' $(if ($state -eq 'same') { 'PASS' } else { 'FAIL' }) "$state (length $($localJsonJwt.Length))"
    $state = if (-not $docsRegistryJwt) { 'blank' } elseif ($docsRegistryJwt -eq $jwt) { 'same' } else { 'DIFFERENT' }
    Add-Result '5' 'Docs registry JwtSecret = Apps secret' $(if ($state -eq 'same') { 'PASS' } else { 'FAIL' }) "$state (length $($docsRegistryJwt.Length))"
}

# ---- 6. registry
if (-not $registry) { Add-Result '6' 'registry key' 'FAIL' "$($expectation.registryKey) missing (WOW6432Node too)" }
else {
    # An update keeps the old credentials, so the administrative passwords that only a fresh install generates stay blank
    $mayBeEmpty = @('REDIS_PWD')
    if ($Mode -eq 'Update') { $mayBeEmpty += 'MYSQL_ROOT_PWD', 'PS_SUPER_PWD' }
    $absent = @($expectation.registryValues | Where-Object { $null -eq $registry.$_ })
    $empty = @($expectation.registryValues | Where-Object { $null -ne $registry.$_ -and "$($registry.$_)".Trim() -eq '' -and $mayBeEmpty -notcontains $_ })
    $status = if ($absent) { 'FAIL' } elseif ($empty) { 'WARN' } else { 'PASS' }
    Add-Result '6' "registry: $(@($expectation.registryValues).Count) values" $status "missing: $($absent -join ',') empty: $($empty -join ',')"
}

# ---- 7. config: the installer writes MACHINE_KEY into appsettings.<environment>.json
$environmentConfig = Join-Path $appDir "config\appsettings.$($expectation.environment).json"
$environmentJson = Read-JsonFile $environmentConfig
$machineKey = if ($environmentJson) { "$($environmentJson.core.machinekey)".Trim() } else { '' }
# A silent 4.0.1 install left the key blank; the update must keep it, since a new key would not open data protected with the old one
$releasedState = if ($Mode -eq 'Update' -and $StateBefore) { Read-JsonFile $StateBefore }
$blankKeyKept = $releasedState -and $environmentJson -and @((Get-Sha256Hex ' '), (Get-Sha256Hex '')) -contains $releasedState.machineKey -and
    $releasedState.machineKey -eq (Get-Sha256Hex $environmentJson.core.machinekey)
$status = if ($blankKeyKept) { 'WARN' } elseif (-not $machineKey) { 'FAIL' } elseif ($registry -and "$($registry.MACHINE_KEY)".Trim() -ne $machineKey) { 'WARN' } else { 'PASS' }
$detail = if ($blankKeyKept) { "blank since the released version, kept by the update in $(Split-Path $environmentConfig -Leaf)" }
    elseif ($status -eq 'WARN') { 'differs from registry MACHINE_KEY' } elseif ($machineKey) { "set in $(Split-Path $environmentConfig -Leaf)" } else { "blank in $(Split-Path $environmentConfig -Leaf)" }
Add-Result '7' 'core.machinekey' $status $detail
$devConfigs = Get-ChildItem (Join-Path $appDir 'config') -Include '*.test.json', '*.dev.json' -Recurse -ErrorAction SilentlyContinue
Add-Result '7' 'no *.test.json / *.dev.json' $(if ($devConfigs) { 'FAIL' } else { 'PASS' }) (($devConfigs.Name) -join ', ')

# ---- 8. OpenResty
$proxyConfigs = Get-ChildItem (Join-Path $expectation.openRestyConfDir 'onlyoffice*.conf') -ErrorAction SilentlyContinue
Add-Result '8' 'OpenResty onlyoffice*.conf' $(if ($proxyConfigs) { 'PASS' } else { 'FAIL' }) (($proxyConfigs.Name) -join ', ')
Add-Result '8' 'APPDIR\nginx moved away' $(if (Test-Path (Join-Path $appDir 'nginx')) { 'FAIL' } else { 'PASS' })

# ---- 9. OpenSearch
$openSearchYml = Get-Content $expectation.opensearch.yml -Raw -ErrorAction SilentlyContinue
$wantedDataPath = Join-Path $appDir $expectation.opensearch.indexDir
$dataPathOk = $openSearchYml -match ('(?m)^path\.data:\s*' + [regex]::Escape($wantedDataPath))
$securityOff = $openSearchYml -match '(?m)^plugins\.security\.disabled:\s*true'
Add-Result '9' 'opensearch.yml' $(if ($dataPathOk -and $securityOff) { 'PASS' } else { 'FAIL' }) "path.data=$dataPathOk ($wantedDataPath) security.disabled=$securityOff"
$jvmOptions = Get-Content $expectation.opensearch.jvm -ErrorAction SilentlyContinue
$heapMin = $expectation.opensearch.heap
$heapMax = $heapMin -replace 'Xms', 'Xmx'
Add-Result '9' "jvm.options $heapMin $heapMax" $(if (($jvmOptions -contains $heapMin) -and ($jvmOptions -contains $heapMax)) { 'PASS' } else { 'FAIL' })
$openSearchVersion = try { ((Invoke-WebRequest 'http://localhost:9200/' -UseBasicParsing -TimeoutSec 20).Content | ConvertFrom-Json).version.number } catch { $_.Exception.Message }
Add-Result '9' "OpenSearch answers, version $($expectation.opensearch.version)" $(if ($openSearchVersion -eq $expectation.opensearch.version) { 'PASS' } else { 'FAIL' }) "$openSearchVersion"

# ---- 10. Fluent Bit
Add-Result '10' 'fluent-bit.conf moved' $(if (Test-Path (Join-Path $expectation.fluentBitConfDir 'fluent-bit.conf')) { 'PASS' } else { 'FAIL' }) $expectation.fluentBitConfDir

# ---- 11. firewall
foreach ($ruleName in $expectation.firewallRules) {
    $rule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    Add-Result '11' "firewall '$ruleName'" $(if ($rule -and "$($rule.Enabled)" -eq 'True') { 'PASS' } else { 'FAIL' })
}

# ---- 12. portal
$appPort = $expectation.appPort
$portalStatus = try { (Invoke-WebRequest "http://localhost:$appPort/" -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 5).StatusCode } catch { $_.Exception.Message }
Add-Result '12' "portal http://localhost:$appPort/" $(if ($portalStatus -eq 200) { 'PASS' } else { 'FAIL' }) "$portalStatus"
$portalVersion = try { ((Invoke-WebRequest "http://localhost:$appPort/api/2.0/settings" -UseBasicParsing -TimeoutSec 60).Content | ConvertFrom-Json).response.version } catch { $_.Exception.Message }
$status = if (-not $expectation.version) { 'WARN' } elseif ("$portalVersion" -like "$($expectation.version)*") { 'PASS' } else { 'FAIL' }
Add-Result '12' 'api/2.0/settings version' $status "$portalVersion"

# ---- 13. license (EE/DE): the installer always sets LICENSE_PATH = [APPDIR]\Data\license.lic
if ($expectation.edition -ne 'CE') {
    $licensePath = if ($environmentJson) { "$($environmentJson.license.file.path)".Trim() } else { '' }
    $expectedLicense = [IO.Path]::GetFullPath((Join-Path $appDir 'Data\license.lic'))
    $licenseInAppDir = $licensePath -and [IO.Path]::IsPathRooted($licensePath) -and [IO.Path]::GetFullPath($licensePath.Replace('/', '\')) -ieq $expectedLicense
    $status = if ($licenseInAppDir) { 'PASS' } else { 'FAIL' }
    $detail = if ($licenseInAppDir -or -not $licensePath) { "'$licensePath' in $(Split-Path $environmentConfig -Leaf)" } else { "'$licensePath' in $(Split-Path $environmentConfig -Leaf), expected $expectedLicense" }
    Add-Result '13' 'license.file.path' $status $detail
    # The portal wizard writes the file, and the checklist runs before it
    Add-Result '13' 'license file present' $(if ($licenseInAppDir -and (Test-Path -LiteralPath $expectedLicense)) { 'PASS' } else { 'INFO' }) 'appears after the portal wizard accepts the license'
}

# ---- 14. MSI log
$msiLogFound = $MsiLog -and (Test-Path $MsiLog)
if ($msiLogFound) {
    $failures = @(Select-String -Path $MsiLog -Pattern 'Return value 3' | Select-Object -First 3)
    Add-Result '14' 'MSI log: no failed actions' $(if ($failures) { 'FAIL' } else { 'PASS' }) (($failures | ForEach-Object { $_.Line.Trim() }) -join ' | ')
    $migration = Select-String -Path $MsiLog -Pattern 'Action ended .*StartMigrationRunner\. Return value (\d)' | Select-Object -Last 1
    $migrationResult = if ($migration) { $migration.Matches[0].Groups[1].Value } else { 'not run' }
    Add-Result '14' 'DB migrations (StartMigrationRunner)' $(if ($migrationResult -eq '1') { 'PASS' } else { 'FAIL' }) "return value: $migrationResult"
}

# ---- 15. hardening: service accounts, priorities, folder and settings key ACLs
if (-not $hardening) { Add-Result '15' 'hardening checks' 'INFO' 'the tested install/win has no LockSecrets: skipped' }
else {
    $serviceInfo = @{}
    foreach ($service in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) { $serviceInfo[$service.Name] = $service }
    $wrongAccounts = @(foreach ($property in $expectation.serviceAccounts.PSObject.Properties) {
        $actual = if ($serviceInfo.ContainsKey($property.Name)) { "$($serviceInfo[$property.Name].StartName)" } else { 'missing' }
        if ($actual -ne $property.Value) { "$($property.Name)=$actual" } })
    $accounts = ($expectation.serviceAccounts.PSObject.Properties | Group-Object Value | ForEach-Object { "$($_.Name) x$($_.Count)" }) -join ', '
    Add-Result '15' 'Apps service accounts' $(if ($wrongAccounts) { 'FAIL' } else { 'PASS' }) $(if ($wrongAccounts) { 'other: ' + ($wrongAccounts -join ', ') } else { $accounts })

    # A WinSW wrapper starts its program as a child process with the priority class of its xml
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $wrongPriorities = @(); $wrongInfraPriorities = @(); $checkedProcesses = 0
    foreach ($property in $expectation.servicePriorities.PSObject.Properties) {
        $service = $serviceInfo[$property.Name]
        if (-not $service -or -not $service.ProcessId) { continue }
        $processIds = @($service.ProcessId) + @($processes | Where-Object { $_.ParentProcessId -eq $service.ProcessId } | ForEach-Object ProcessId)
        foreach ($processId in $processIds) {
            $priority = try { "$([System.Diagnostics.Process]::GetProcessById([int]$processId).PriorityClass)" } catch { 'unreadable' }
            $checkedProcesses++
            if ($priority -eq $property.Value) { continue }
            if ($property.Name -like 'Apps.*') { $wrongPriorities += "$($property.Name)#${processId}=$priority" } else { $wrongInfraPriorities += "$($property.Name)#${processId}=$priority" }
        }
    }
    $wantedPriorities = ($expectation.servicePriorities.PSObject.Properties.Value | Select-Object -Unique) -join ','
    # OpenResty and OpenSearch come from the Prerequisites, which an update of Apps alone does not reinstall: there an old priority only warns
    $infraStatus = if ($Mode -eq 'Update') { 'WARN' } else { 'FAIL' }
    $status = if ($wrongPriorities) { 'FAIL' } elseif ($wrongInfraPriorities) { $infraStatus } elseif ($checkedProcesses) { 'PASS' } else { 'WARN' }
    $detail = if ($wrongPriorities -or $wrongInfraPriorities) { (@($wrongPriorities) + @($wrongInfraPriorities)) -join ', ' } else { "$checkedProcesses processes" }
    Add-Result '15' "WinSW process priority $wantedPriorities" $status $detail

    # APPDIR: protected DACL with exactly the entries of the installer SDDL
    $wantedAces = @(ConvertFrom-SddlAces $hardening.appDirSddl)
    $appDirAcl = Get-Acl -LiteralPath $appDir -ErrorAction SilentlyContinue
    if (-not $appDirAcl) { Add-Result '15' 'APPDIR ACL' 'FAIL' 'unreadable' }
    else {
        $rules = Get-EffectiveRules $appDirAcl
        $extraSids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique | Where-Object { $wantedAces.Sid -notcontains $_ })
        $wrongMasks = @($wantedAces | Where-Object { (Get-SidMask $rules $_.Sid) -ne $_.Mask } | ForEach-Object { '{0}=0x{1:x} (expected 0x{2:x})' -f $_.Sid, (Get-SidMask $rules $_.Sid), $_.Mask })
        $ok = $appDirAcl.AreAccessRulesProtected -and -not $extraSids -and -not $wrongMasks
        Add-Result '15' 'APPDIR ACL = installer SDDL (protected)' $(if ($ok) { 'PASS' } else { 'FAIL' }) "protected=$($appDirAcl.AreAccessRulesProtected); extra: $($extraSids -join ','); masks: $($wrongMasks -join ','); $(Format-Rules $rules)"
    }

    # Writable folders: LocalService Modify; nothing for broad groups
    $modifyMask = [int][Security.AccessControl.FileSystemRights]::Modify
    foreach ($relativeDir in $hardening.writableDirs) {
        $folder = Join-Path $appDir $relativeDir
        $acl = Get-Acl -LiteralPath $folder -ErrorAction SilentlyContinue
        if (-not $acl) { Add-Result '15' "ACL $relativeDir" 'FAIL' 'missing'; continue }
        $rules = Get-EffectiveRules $acl
        $broad = @($rules | Where-Object { $BroadSids -contains $_.IdentityReference.Value } | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
        $localServiceModify = ((Get-SidMask $rules 'S-1-5-19') -band $modifyMask) -eq $modifyMask
        Add-Result '15' "ACL $relativeDir (LocalService Modify)" $(if ($localServiceModify -and -not $broad) { 'PASS' } else { 'FAIL' }) "LocalService modify=$localServiceModify; broad: $($broad -join ',')"
    }

    # Everything else stays read-only for LocalService and closed to broad groups: APPDIR children, config\*, tools\*
    $writeMask = [int]([Security.AccessControl.FileSystemRights]::WriteData -bor [Security.AccessControl.FileSystemRights]::AppendData -bor
        [Security.AccessControl.FileSystemRights]::WriteAttributes -bor [Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor [Security.AccessControl.FileSystemRights]::Delete)
    $writableRoots = @($hardening.writableDirs | ForEach-Object { ($_ -split '\\')[0] } | Where-Object { $_ -ne 'services' })
    $items = @(Get-ChildItem -LiteralPath $appDir -Force -ErrorAction SilentlyContinue | Where-Object { $writableRoots -notcontains $_.Name }) +
             @(Get-ChildItem -LiteralPath (Join-Path $appDir 'config'), (Join-Path $appDir 'tools') -Force -ErrorAction SilentlyContinue)
    $openItems = @(foreach ($item in $items) {
        $acl = Get-Acl -LiteralPath $item.FullName -ErrorAction SilentlyContinue
        if (-not $acl) { continue }
        $rules = Get-EffectiveRules $acl
        $broad = @($rules | Where-Object { $BroadSids -contains $_.IdentityReference.Value })
        if ($broad -or ((Get-SidMask $rules 'S-1-5-19') -band $writeMask)) { $item.FullName.Substring($appDir.Length) } })
    Add-Result '15' "read-only for LocalService, no broad groups: $($items.Count) items (APPDIR children, config, tools)" $(if ($openItems) { 'FAIL' } else { 'PASS' }) "$($openItems.Count) open: $(($openItems | Select-Object -First 8) -join ', ')"

    # Settings key: protected, only the trustees of the installer SDDL
    $keyAcl = Get-AppsRegistryKeyAcl $expectation.registryKey
    if (-not $keyAcl) { Add-Result '15' 'settings key ACL' 'FAIL' 'key missing in the 32-bit view' }
    else {
        $wantedKeySids = @(ConvertFrom-SddlAces $hardening.registryKeySddl | ForEach-Object Sid)
        $rules = Get-EffectiveRules $keyAcl
        $keySids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
        $extraSids = @($keySids | Where-Object { $wantedKeySids -notcontains $_ })
        $missingSids = @($wantedKeySids | Where-Object { $keySids -notcontains $_ })
        $ok = $keyAcl.AreAccessRulesProtected -and -not $extraSids -and -not $missingSids
        Add-Result '15' 'settings key ACL = installer SDDL (protected)' $(if ($ok) { 'PASS' } else { 'FAIL' }) "protected=$($keyAcl.AreAccessRulesProtected); $(Format-Rules $rules)"
    }
    if ($msiLogFound) {
        $locked = Select-String -Path $MsiLog -SimpleMatch -Pattern $hardening.lockedLogLine -Quiet
        $lockError = Select-String -Path $MsiLog -SimpleMatch -Pattern 'ERROR: could not restrict access' | Where-Object { $_.Line -notmatch 'Write-Output' } | Select-Object -First 1
        Add-Result '15' 'MSI log: LockSecrets restricted the key and APPDIR' $(if ($locked -and -not $lockError) { 'PASS' } else { 'FAIL' }) "success line=$locked; error line=$([bool]$lockError)"
    }
}

# ---- 16. credentials: own database and broker users on a fresh install, the stored ones keep working on an update
$dbName = Get-TrimmedValue $registry 'DB_NAME'
$dbUser = Get-TrimmedValue $registry 'DB_USER'
$dbPassword = Get-TrimmedValue $registry 'DB_PWD'
$dbPort = Get-TrimmedValue $registry 'DB_PORT'; if (-not $dbPort) { $dbPort = '3306' }
$mysqlRootPassword = Get-TrimmedValue $registry 'MYSQL_ROOT_PWD'
$postgresSuperPassword = Get-TrimmedValue $registry 'PS_SUPER_PWD'
$postgresUser = Get-TrimmedValue $registry 'PS_DB_USER'
$postgresPassword = Get-TrimmedValue $registry 'PS_DB_PWD'
$postgresDb = Get-TrimmedValue $registry 'PS_DB_NAME'
$postgresPort = Get-TrimmedValue $registry 'PS_DB_PORT'; if (-not $postgresPort) { $postgresPort = '5432' }
$amqpUser = Get-TrimmedValue $registry 'AMQP_USER'
$amqpPassword = Get-TrimmedValue $registry 'AMQP_PWD'

if ($hardening -and $Mode -eq 'Fresh') {
    Add-Result '16' 'MYSQL_ROOT_PWD and PS_SUPER_PWD stored' $(if ($mysqlRootPassword -and $postgresSuperPassword) { 'PASS' } else { 'FAIL' }) "lengths $($mysqlRootPassword.Length) / $($postgresSuperPassword.Length)"
    $query = Invoke-MySqlQuery 'root' $mysqlRootPassword 'SELECT 1' $dbPort
    Add-Result '16' 'MySQL root with MYSQL_ROOT_PWD' $(if ($query.Code -eq 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
    $query = Invoke-MySqlQuery 'root' 'root' 'SELECT 1' $dbPort
    Add-Result '16' "MySQL root/'root' rejected" $(if ($query.Code -gt 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
    $wantedUser = $dbName.Substring(0, [Math]::Min([int]$hardening.dbNameMaxLength, $dbName.Length)) + '_user'
    $differs = $dbPassword -and $dbPassword -ne $mysqlRootPassword
    Add-Result '16' 'DB_USER is the application user' $(if ($dbUser -eq $wantedUser -and $differs) { 'PASS' } else { 'FAIL' }) "DB_USER=$dbUser (expected $wantedUser); password differs from root: $differs"
    $query = Invoke-MySqlQuery $dbUser $dbPassword "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$dbName'" $dbPort
    $tableCount = 0; [void][int]::TryParse("$($query.Output)", [ref]$tableCount)
    Add-Result '16' 'MySQL application user sees the Apps tables' $(if ($query.Code -eq 0 -and $tableCount -gt 10) { 'PASS' } else { 'FAIL' }) "exit $($query.Code), $tableCount tables in $dbName"
    $query = Invoke-MySqlQuery $dbUser $dbPassword 'SHOW GRANTS FOR CURRENT_USER()' $dbPort
    $grants = $query.Output -replace "IDENTIFIED BY '[^']*'", ''
    $globalGrant = $grants -match 'GRANT (?!USAGE ON \*\.\*)[^`]*ON \*\.\*'
    Add-Result '16' 'MySQL application user: grants on its database only' $(if ($query.Code -eq 0 -and -not $globalGrant) { 'PASS' } else { 'FAIL' }) $grants
    if ($hardening.postgresSuper) {
        $query = Invoke-PsqlQuery 'postgres' $postgresSuperPassword 'postgres' 'SELECT 1' $postgresPort
        Add-Result '16' 'PostgreSQL postgres with PS_SUPER_PWD' $(if ($query.Code -eq 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
        $query = Invoke-PsqlQuery 'postgres' 'postgres' 'postgres' 'SELECT 1' $postgresPort
        Add-Result '16' "PostgreSQL postgres/'postgres' rejected" $(if ($query.Code -gt 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
    }
    $brokerUsers = Get-RabbitMqUsers
    $listed = "$brokerUsers" -match "(^|\s)$([regex]::Escape($hardening.rabbitMqUser))(\s|$)"
    $ok = $amqpUser -eq $hardening.rabbitMqUser -and $amqpPassword -and $listed
    Add-Result '16' "RabbitMQ user '$($hardening.rabbitMqUser)' for Apps" $(if ($ok) { 'PASS' } else { 'FAIL' }) "AMQP_USER=$amqpUser, password length $($amqpPassword.Length), rabbitmqctl list_users: $(("$brokerUsers" -replace '\s+', ' ').Trim())"
} else {
    $query = Invoke-MySqlQuery $dbUser $dbPassword 'SELECT 1' $dbPort
    Add-Result '16' "MySQL DB_USER ($dbUser) with DB_PWD" $(if ($query.Code -eq 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
    if ($hardening) { Add-Result '16' 'fresh-install credentials' 'INFO' "update: own MySQL/RabbitMQ users are created on a fresh install only; MYSQL_ROOT_PWD set=$([bool]$mysqlRootPassword), PS_SUPER_PWD set=$([bool]$postgresSuperPassword), AMQP_USER=$amqpUser" }
}
# Connection strings that point to the Apps database must use DB_USER
$connectionUsers = @(Get-ChildItem (Join-Path $appDir 'config\*.json') -ErrorAction SilentlyContinue | ForEach-Object {
    Select-String -LiteralPath $_.FullName -Pattern "Database=$([regex]::Escape($dbName));[^`"]*User ID=([^;`"]+);" -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } } | Sort-Object -Unique)
Add-Result '16' "Apps connection strings to $dbName use DB_USER" $(if ($connectionUsers.Count -and -not ($connectionUsers | Where-Object { $_ -ne $dbUser })) { 'PASS' } else { 'FAIL' }) "users: $($connectionUsers -join ',')"
$rabbitConfig = Get-ChildItem (Join-Path $appDir 'config\*.json') -ErrorAction SilentlyContinue | ForEach-Object { Read-JsonFile $_.FullName } | Where-Object { $_ -and $_.PSObject.Properties['RabbitMQ'] } | Select-Object -First 1
if ($rabbitConfig) {
    $ok = $rabbitConfig.RabbitMQ.UserName -eq $amqpUser -and "$($rabbitConfig.RabbitMQ.Password)" -eq $amqpPassword
    Add-Result '16' 'Apps RabbitMQ config = AMQP_USER/AMQP_PWD' $(if ($ok) { 'PASS' } else { 'FAIL' }) "UserName=$($rabbitConfig.RabbitMQ.UserName)"
}
$query = Invoke-PsqlQuery $postgresUser $postgresPassword $postgresDb 'SELECT 1' $postgresPort
Add-Result '16' "PostgreSQL PS_DB_USER ($postgresUser) with PS_DB_PWD" $(if ($query.Code -eq 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"

# ---- 17. Docs credentials: the same database password and broker user as Apps, its tables on EE/DE
if ($docs) {
    $docsDbPassword = Get-TrimmedValue $docsRegistry 'DbPwd'
    $docsDbUser = Get-TrimmedValue $docsRegistry 'DbUser'; if (-not $docsDbUser) { $docsDbUser = $postgresUser }
    $state = if (-not $docsDbPassword) { 'blank' } elseif ($docsDbPassword -eq $postgresPassword) { 'same' } else { 'DIFFERENT' }
    Add-Result '17' 'Docs DbPwd = Apps PS_DB_PWD' $(if ($state -eq 'same') { 'PASS' } else { 'FAIL' }) "$state (length $($docsDbPassword.Length))"
    $query = Invoke-PsqlQuery $docsDbUser $docsDbPassword $postgresDb "SELECT to_regclass('public.task_result') IS NOT NULL" $postgresPort
    Add-Result '17' "Docs database login as $docsDbUser" $(if ($query.Code -eq 0) { 'PASS' } else { 'FAIL' }) "exit $($query.Code)"
    $hasTable = $query.Code -eq 0 -and "$($query.Output)" -eq 't'
    $status = if ($hasTable) { 'PASS' } elseif ($expectation.edition -eq 'CE') { 'INFO' } else { 'FAIL' }
    Add-Result '17' 'Docs table task_result' $status $(if ($expectation.edition -eq 'CE') { "exists=$hasTable (Docs CE keeps no data there)" } else { "exists=$hasTable" })
    $docsRabbitUser = Get-TrimmedValue $docsRegistry 'RabbitMqUser'
    if (-not $docsRabbitUser -and $docsLocalJson -and "$($docsLocalJson.rabbitmq.url)" -match '://([^:@/]+)') { $docsRabbitUser = $Matches[1] }
    if (-not $docsRabbitUser) { $docsRabbitUser = 'guest' }
    $status = if ($docsRabbitUser -eq $amqpUser) { 'PASS' } elseif ($docsRabbitUser -eq 'guest') { 'WARN' } else { 'FAIL' }
    Add-Result '17' 'Docs RabbitMQ user = Apps AMQP_USER' $status "Docs $docsRabbitUser, Apps $amqpUser$(if ($status -eq 'WARN') { ' (known: the silent path installs Docs before Apps creates its user)' })"
}

# ---- 18. leftovers and leaks
$tempRoots = @(Get-TempRoots)
$leftDirs = @(foreach ($root in $tempRoots) {
    Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'onlyoffice-apps-docs-params-*' -or $_.Name -like 'rabbitmqctl-*' } | ForEach-Object FullName })
$leftFiles = @(foreach ($root in $tempRoots) { Get-ChildItem -LiteralPath $root -Filter 'docs-params.ini' -Recurse -Depth 2 -Force -ErrorAction SilentlyContinue | ForEach-Object FullName })
Add-Result '18' 'no parameters or rabbitmqctl folder left in any TEMP' $(if ($leftDirs -or $leftFiles) { 'FAIL' } else { 'PASS' }) "$($tempRoots.Count) TEMP folders; left: $((@($leftDirs) + @($leftFiles)) -join ', ')"
$undefinedDirs = @(Get-ChildItem -LiteralPath $appDir -Directory -Recurse -Depth 6 -Filter 'undefined' -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName.Substring($appDir.Length) })
# Node services of versions before the hardening wrote there; an update keeps the old folder, so it only warns
$undefinedStatus = if (-not $undefinedDirs) { 'PASS' } elseif ($Mode -eq 'Update') { 'WARN' } else { 'FAIL' }
Add-Result '18' "no 'undefined' folder under APPDIR (Node log path)" $undefinedStatus ($undefinedDirs -join ', ')
$deniedLogs = @(Get-ChildItem (Join-Path $appDir 'Logs') -File -Filter '*.log' -ErrorAction SilentlyContinue |
    Where-Object { Select-String -LiteralPath $_.FullName -Pattern '\b(EPERM|EACCES)\b' -Quiet } | ForEach-Object Name)
Add-Result '18' 'no EPERM/EACCES in APPDIR\Logs' $(if ($deniedLogs) { 'FAIL' } else { 'PASS' }) ($deniedLogs -join ', ')

# Secrets the sampled command lines must not contain; well-known defaults are left out, they are no secret
$secretNames = 'MYSQL_ROOT_PWD', 'PS_SUPER_PWD', 'DB_PWD', 'PS_DB_PWD', 'AMQP_PWD', 'DOCUMENT_SERVER_JWT_SECRET', 'IDENTITY_ENCRYPTION_SECRET', 'DASHBOARDS_PWD', 'MACHINE_KEY'
$secrets = [ordered]@{}
foreach ($name in $secretNames) { $secrets[$name] = Get-TrimmedValue $registry $name }
foreach ($name in 'JwtSecret', 'DbPwd', 'RabbitMqPwd') { $secrets["Docs $name"] = Get-TrimmedValue $docsRegistry $name }
$wellKnown = $WellKnownValues
if ($CommandLines -and (Test-Path -LiteralPath $CommandLines)) {
    try {
        $sampled = [IO.File]::ReadAllText($CommandLines)
        $lineCount = @(Get-Content -LiteralPath $CommandLines).Count
        $leaked = @($secrets.Keys | Where-Object { $secrets[$_].Length -ge 8 -and $wellKnown -notcontains $secrets[$_] -and $sampled.Contains($secrets[$_]) })
        # The bootstrapper of an update passes the stored properties to msiexec; known, so an update only warns
        $status = if (-not $leaked) { 'PASS' } elseif ($Mode -eq 'Update') { 'WARN' } else { 'FAIL' }
        Add-Result '18' 'no secret on sampled process command lines' $status "$lineCount distinct command lines; found: $($leaked -join ',')"
    } finally { Remove-Item -LiteralPath $CommandLines -Force -ErrorAction SilentlyContinue }
} else { Add-Result '18' 'no secret on sampled process command lines' 'INFO' 'no sampled command lines' }

if ($msiLogFound) {
    $notSaved = @(Select-String -Path $MsiLog -SimpleMatch -Pattern 'WARNING: the new passwords are not saved' | Where-Object { $_.Line -notmatch 'Write-Output' })
    Add-Result '18' "MSI log: no 'new passwords are not saved'" $(if ($notSaved) { 'FAIL' } else { 'PASS' }) "$($notSaved.Count) lines"
    $connectionErrors = @(Select-String -Path $MsiLog -Pattern 'password authentication failed|Access denied for user|could not connect to server|Unable to connect to any of the specified MySQL hosts|Unable to create the application database user,|Unable to create the RabbitMQ user,' |
        Where-Object { $_.Line -notmatch 'Write-Output|^\s*#' })
    $patterns = ($connectionErrors | ForEach-Object { $_.Matches[0].Value } | Select-Object -Unique) -join '; '
    Add-Result '18' 'MSI log: no database or broker connection errors' $(if ($connectionErrors) { 'FAIL' } else { 'PASS' }) "$($connectionErrors.Count) lines $patterns"
}

# ---- output
exit (Complete-CiResults -Results $results -Title $Title -Out $Out)
