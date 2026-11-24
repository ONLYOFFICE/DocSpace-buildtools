# Shared helpers of the Windows installer CI: annotations, job summary, installed product lookup, secret masking.
# Works in Windows PowerShell 5.1 and PowerShell 7; keep this file ASCII (5.1 reads BOM-less files as ANSI).

$script:DefaultRegistryKey = 'HKLM:\Software\Ascensio System SIA\ONLYOFFICE Apps'
# Docs keeps its settings and secrets in the 64-bit view
$script:DocsRegistryKey = 'HKLM:\SOFTWARE\ONLYOFFICE\DocumentServer'
# Machine-wide variables of the runner image that point to its own JDK and PostgreSQL, not to the ones Apps installs
$script:ConflictingEnvNames = @('JAVA_HOME', 'PGBIN', 'PGDATA', 'PGROOT', 'PGUSER', 'PGPASSWORD')
# Property, registry and JSON names whose values are secrets
$script:SecretNamePattern = '(?i)(pwd|pass|secret|machinekey|machine_key|token|apikey|api_key|private)'
$script:SecretNameCore = '(?:pwd|pass|secret|machinekey|machine_key|token|apikey|api_key|private)'
# SDDL trustee aliases used by the installer, as SIDs
$script:SddlAliases = @{ SY = 'S-1-5-18'; BA = 'S-1-5-32-544'; LS = 'S-1-5-19'; NS = 'S-1-5-20'; BU = 'S-1-5-32-545'; AU = 'S-1-5-11'; WD = 'S-1-1-0' }
# Groups that must never get access to the install folder or the settings key: Users, Authenticated Users, Everyone, Guests
$script:BroadSids = @('S-1-5-32-545', 'S-1-5-11', 'S-1-1-0', 'S-1-5-32-546')
# Default passwords of older installs are public knowledge and also user and database names, so they are neither masked nor searched for
$script:WellKnownValues = @('root', 'postgres', 'guest', 'onlyoffice')

function Write-CiAnnotation {
    param([ValidateSet('error', 'warning', 'notice')][string]$Level, [string]$Message)
    if ($env:GITHUB_ACTIONS -eq 'true') {
        # Workflow commands need %, CR and LF escaped
        $escaped = $Message.Replace('%', '%25').Replace("`r", '%0D').Replace("`n", '%0A')
        Write-Host "::${Level}::$escaped"
    } else {
        Write-Host "[$($Level.ToUpper())] $Message"
    }
}

function Add-CiSummary {
    param([string[]]$Lines)
    # UTF-8 without a byte order mark: Windows PowerShell 5.1 Add-Content would start an empty file with one
    if ($env:GITHUB_STEP_SUMMARY) { [IO.File]::AppendAllText($env:GITHUB_STEP_SUMMARY, (($Lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false))) }
}

function Set-CiEnv {
    param([string]$Name, [string]$Value)
    Set-Item -Path "Env:$Name" -Value $Value
    if ($env:GITHUB_ENV) { [IO.File]::AppendAllText($env:GITHUB_ENV, "$Name=$Value`n", (New-Object Text.UTF8Encoding($false))) }
}

function ConvertTo-CiMarkdownTable {
    param([object[]]$Rows, [string[]]$Columns)
    $header = '| ' + ($Columns -join ' | ') + ' |'
    $divider = '|' + (($Columns | ForEach-Object { '---' }) -join '|') + '|'
    $body = foreach ($row in $Rows) {
        $cells = foreach ($column in $Columns) { "$($row.$column)".Replace('|', '\|').Replace("`r", ' ').Replace("`n", ' ') }
        '| ' + ($cells -join ' | ') + ' |'
    }
    @($header, $divider) + @($body)
}

# Writes a PASS/WARN/FAIL result list to the job summary and turns FAIL and WARN rows into annotations
function Publish-CiResults {
    param([object[]]$Results, [string]$Title)
    $counts = ($Results | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ' '
    $failed = @($Results | Where-Object status -eq 'FAIL')
    $open = if ($failed.Count) { ' open' } else { '' }
    $columns = @($Results[0].PSObject.Properties.Name)
    Add-CiSummary (@("<details$open><summary>$Title - $counts</summary>", '') + (ConvertTo-CiMarkdownTable $Results $columns) + @('', '</details>', ''))
    foreach ($row in $Results) {
        $label = if ($row.PSObject.Properties['id']) { "[$($row.id)] $($row.check)" } else { $row.check }
        if ($row.status -eq 'FAIL') { Write-CiAnnotation error "${Title}: $label - $($row.detail)" }
        elseif ($row.status -eq 'WARN') { Write-CiAnnotation warning "${Title}: $label - $($row.detail)" }
    }
}

# Prints the result table, writes it as JSON and to the job summary; returns the FAIL count capped for an exit code
function Complete-CiResults {
    param([object[]]$Results, [string]$Title, [string]$Out)
    $Results | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
    $counts = $Results | Group-Object status | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Host "SUMMARY: $($counts -join ' ')"
    if ($Out) { $Results | ConvertTo-Json -Depth 3 | Set-Content -Path $Out -Encoding UTF8 }
    Publish-CiResults -Results $Results -Title $Title
    # Exit codes wrap at 256, so the FAIL count is capped
    [math]::Min(@($Results | Where-Object status -eq 'FAIL').Count, 255)
}

# SHA-256 of a string as hex; $null stays $null so an absent value differs from an empty one
function Get-Sha256Hex {
    param([object]$Value)
    if ($null -eq $Value) { return $null }
    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { -join ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) } finally { $sha.Dispose() }
}

function Get-UninstallEntries {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName }
}

# Finds the installed Apps and Docs and the Apps folder (APPDIR, with a trailing backslash)
function Get-AppsInstallation {
    $entries = @(Get-UninstallEntries)
    $apps = $entries | Where-Object { $_.DisplayName -like 'ONLYOFFICE Apps*' -and $_.PSChildName -match '^\{' } | Select-Object -First 1
    $docs = $entries | Where-Object { $_.PSChildName -eq 'ONLYOFFICE DocumentServer_is1' } | Select-Object -First 1
    $appDir = $null
    if ($apps -and $apps.InstallLocation) { $appDir = $apps.InstallLocation }
    if (-not $appDir) {
        # Fallback: the WinSW wrapper of a service lives in APPDIR\tools
        $service = Get-CimInstance Win32_Service -Filter "Name='Apps.Login'" -ErrorAction SilentlyContinue
        if ($service) { $appDir = Split-Path (Split-Path ($service.PathName.Trim('"') -replace '"? .*$', '')) }
    }
    if ($appDir) { $appDir = $appDir.TrimEnd('\') + '\' }
    [pscustomobject]@{ Entries = $entries; Apps = $apps; Docs = $docs; AppDir = $appDir }
}

# Edition of a Docs uninstall entry from its display name, which also carries the version
function Get-DocsEdition {
    param([string]$DisplayName)
    if (-not $DisplayName) { return $null }
    switch -Regex ($DisplayName) { 'Enterprise|\bEE\b' { 'EE' } 'Developer|\bDE\b' { 'DE' } default { 'CE' } }
}

# Returns the existing Apps registry key: the 32-bit package writes it under WOW6432Node on 64-bit Windows
function Resolve-AppsRegistryKey {
    param([string]$RegistryKey = $script:DefaultRegistryKey)
    $wowKey = $RegistryKey -replace '^HKLM:\\Software\\', 'HKLM:\SOFTWARE\WOW6432Node\'
    foreach ($candidate in @($RegistryKey, $wowKey)) { if (Test-Path $candidate) { return $candidate } }
    $wowKey
}

# Access rules of the Apps settings key in the 32-bit view, where the installer locks it; $null when the key is missing
function Get-AppsRegistryKeyAcl {
    param([string]$RegistryKey = $script:DefaultRegistryKey)
    $subKey = $RegistryKey -replace '^HKLM:\\', ''
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
    try {
        $key = $base.OpenSubKey($subKey)
        if (-not $key) { return $null }
        try { $key.GetAccessControl() } finally { $key.Close() }
    } finally { $base.Close() }
}

function Read-JsonFile {
    param([string]$Path)
    try { Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
}

# TEMP folders of the machine and of every profile, with the numbered per-session subfolders
function Get-TempRoots {
    $userTemps = @(Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'AppData\Local\Temp' } | Where-Object { Test-Path -LiteralPath $_ })
    $sessionTemps = @($userTemps | ForEach-Object {
        Get-ChildItem -LiteralPath $_ -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\d+$' } | ForEach-Object FullName })
    @("$env:SystemRoot\Temp", "$env:SystemRoot\SystemTemp", $env:TEMP) + $userTemps + $sessionTemps |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique
}

# Creates a TEMP folder that only SYSTEM and Administrators can open, for files that hold a secret for a moment
function New-RestrictedTempDir {
    param([string]$Prefix)
    $directory = Join-Path $env:TEMP ($Prefix + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $directory | Out-Null
    $security = New-Object System.Security.AccessControl.DirectorySecurity
    $security.SetSecurityDescriptorSddlForm('D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
    Set-Acl -LiteralPath $directory -AclObject $security
    $directory
}

# Allow ACEs of an SDDL string as objects with the trustee SID and the access mask
function ConvertFrom-SddlAces {
    param([string]$Sddl)
    $rightsByName = @{ FA = 0x1F01FF; KA = 0xF003F; GA = 0x10000000 }
    foreach ($match in [regex]::Matches($Sddl, '\(A;[^;]*;([^;]*);;;([^)]*)\)')) {
        $rightsText = $match.Groups[1].Value
        $mask = if ($rightsByName.ContainsKey($rightsText)) { $rightsByName[$rightsText] } elseif ($rightsText -match '^0x[0-9a-fA-F]+$') { [Convert]::ToInt32($rightsText, 16) } else { $null }
        $trustee = $match.Groups[2].Value
        $sid = if ($script:SddlAliases.ContainsKey($trustee)) { $script:SddlAliases[$trustee] } else { $trustee }
        [pscustomobject]@{ Sid = $sid; Mask = $mask }
    }
}

# Collects string values under secret-like names in a parsed JSON tree; $Path is the dotted key path
function Get-JsonSecretStrings {
    param($Node, [string]$Path = '')
    if ($null -eq $Node) { return }
    if ($Node -is [string]) {
        $leaf = ($Path -split '\.')[-1]
        # Docs keeps its secrets as secret.<kind>.string
        if ($leaf -match $script:SecretNamePattern -or ($leaf -eq 'string' -and $Path -match $script:SecretNamePattern)) { $Node }
        # Connection strings and AMQP URLs carry passwords inside other values
        foreach ($match in [regex]::Matches($Node, '(?i)(?:password|pwd)\s*=\s*([^;"]+)')) { $match.Groups[1].Value }
        foreach ($match in [regex]::Matches($Node, '://[^:/@\s]+:([^@/\s]+)@')) { $match.Groups[1].Value }
        return
    }
    if ($Node -is [System.Collections.IEnumerable]) { foreach ($item in $Node) { Get-JsonSecretStrings $item $Path }; return }
    if ($Node -is [pscustomobject]) {
        foreach ($property in $Node.PSObject.Properties) { Get-JsonSecretStrings $property.Value "$Path.$($property.Name)" }
    }
}

# Secret values of the current installation: Apps and Docs registry, Apps config and Docs local.json
function Get-AppsSecretValues {
    param([string]$RegistryKey = $script:DefaultRegistryKey)
    $values = New-Object System.Collections.Generic.List[string]
    foreach ($keyPath in @((Resolve-AppsRegistryKey $RegistryKey), $script:DocsRegistryKey)) {
        $registry = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue
        if (-not $registry) { continue }
        # PSPath, PSChildName and the like are added by Get-ItemProperty; PS_SUPER_PWD and PS_DB_PWD are real values
        foreach ($property in $registry.PSObject.Properties) {
            if ($property.Name -notmatch '^PS[A-Z]' -and $property.Name -match $script:SecretNamePattern) { $values.Add("$($property.Value)") }
        }
    }
    $installation = Get-AppsInstallation
    $jsonFiles = @()
    if ($installation.AppDir) { $jsonFiles += Get-ChildItem (Join-Path $installation.AppDir 'config\*.json') -ErrorAction SilentlyContinue }
    if ($installation.Docs -and $installation.Docs.InstallLocation) {
        $jsonFiles += Get-ChildItem (Join-Path $installation.Docs.InstallLocation 'config\local*.json') -ErrorAction SilentlyContinue
    }
    foreach ($file in $jsonFiles) { foreach ($secret in (Get-JsonSecretStrings (Read-JsonFile $file.FullName))) { $values.Add("$secret") } }
    # Short values are dropped (they would redact ordinary words); dedupe before sorting, as Sort-Object -Unique drops equal lengths
    @($values | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -ge 6 -and $script:WellKnownValues -notcontains $_ } | Select-Object -Unique | Sort-Object Length -Descending)
}

# Tells GitHub Actions to hide these values in all further log output
function Register-CiSecretMask {
    param([string[]]$Values)
    if ($env:GITHUB_ACTIONS -ne 'true') { return }
    foreach ($value in $Values) { if ($value) { Write-Host "::add-mask::$value" } }
}

# Replaces secret values, and values of secret-like MSI properties, with ***
function Protect-CiText {
    param([string]$Text, [string[]]$Values)
    if (-not $Text) { return $Text }
    foreach ($value in $Values) { if ($value) { $Text = $Text.Replace($value, '***') } }
    # MSI verbose logs print property values on property changes and in the final property dump
    $Text = [regex]::Replace($Text, "(?im)^[^\r\n]*PROPERTY CHANGE: (?:Adding|Modifying) \S*$($script:SecretNameCore)\S* property\.[^\r\n]*",
        { param($match) [regex]::Replace($match.Value, "'[^']*'", "'***'") })
    $Text = [regex]::Replace($Text, "(?im)^(Property\([SCN]\): \S*$($script:SecretNameCore)\S* = )[^\r\n]*", '$1***')
    # Registry writes of the MSI script: Executing op: RegAddValue(Name=MYSQL_ROOT_PWD,Value=...,)
    $Text = [regex]::Replace($Text, "(?i)(RegAddValue\(Name=[^,]*$($script:SecretNameCore)[^,]*,Value=)[^,\r\n]*", '$1***')
    # Command lines (/JWT_SECRET="..." of the Docs prerequisite, DB_PWD=...) and connection strings (Password=...)
    $Text = [regex]::Replace($Text, '(?i)(\b\w*' + $script:SecretNameCore + '\w*\s*=\s*)("[^"\r\n]*"|[^\s;"]+)', '$1***')
    # Credentials inside URLs such as amqp://user:password@host
    $Text = [regex]::Replace($Text, '(://[^:/@\s]+:)[^@/\s]+@', '$1***@')
    $Text
}

# Removes the runner image variables that would point Apps services to foreign JDK and PostgreSQL installs
function Clear-ConflictingProcessEnv {
    foreach ($name in $script:ConflictingEnvNames) { Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue }
}

Export-ModuleMember -Function * -Variable DefaultRegistryKey, DocsRegistryKey, ConflictingEnvNames, BroadSids, WellKnownValues
