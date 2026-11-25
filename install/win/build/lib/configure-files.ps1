# Adapts the configs copied into out\Files to Windows: OpenResty paths and headers, Fluent Bit, log levels, URLs, unused services.
# The edits match the GNU sed calls build-batch.bat used to make, including their output: lines end with LF and a BOM is kept.
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilesDir,
    [Parameter(Mandatory = $true)][string]$Version    # BUILD_VERSION.BUILD_NUMBER, written to appsettings.json
)

$ErrorActionPreference = 'Stop'
$FilesDir = (Resolve-Path -LiteralPath $FilesDir).ProviderPath
$Nginx = Join-Path $FilesDir 'nginx\conf'
$Config = Join-Path $FilesDir 'config'

# Reads a file as lines without CR, as sed does, and remembers the BOM and the final line break
function Read-Lines([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $offset = if ($bom) { 3 } else { 0 }
    $text = [Text.Encoding]::UTF8.GetString($bytes, $offset, $bytes.Length - $offset)
    $finalBreak = $text.EndsWith("`n")
    if ($finalBreak) { $text = $text.Substring(0, $text.Length - 1) }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($line in $text.Split("`n")) { $lines.Add($line.TrimEnd("`r")) }
    return [pscustomobject]@{ Bom = $bom; FinalBreak = $finalBreak; Lines = $lines }
}

function Write-Lines([string]$Path, $File) {
    $text = [string]::Join("`n", $File.Lines)
    if ($File.FinalBreak) { $text += "`n" }
    $body = [Text.Encoding]::UTF8.GetBytes($text)
    $bytes = if ($File.Bom) { [byte[]](0xEF, 0xBB, 0xBF) + $body } else { $body }
    [IO.File]::WriteAllBytes($Path, $bytes)
}

# Applies a script block to the lines of each file; the block gets and returns a list of lines
function Edit-Files([string[]]$Paths, [scriptblock]$Edit) {
    foreach ($path in $Paths) {
        $file = Read-Lines $path
        $file.Lines = [System.Collections.Generic.List[string]]@(& $Edit $file.Lines)
        Write-Lines $path $file
    }
}

# s/pattern/replacement/ (first match of a line) or with -All s/.../g; -Unless skips lines that match it (sed /regex/!s)
function Set-Text($Lines, [string]$Pattern, [string]$Replacement, [switch]$All, [string]$Unless) {
    $regex = New-Object System.Text.RegularExpressions.Regex($Pattern)
    foreach ($line in $Lines) {
        if ($Unless -and $line -cmatch $Unless) { $line; continue }
        if ($All) { $regex.Replace($line, $Replacement) } else { $regex.Replace($line, $Replacement, 1) }
    }
}

# /regex/d
function Remove-Lines($Lines, [string]$Pattern) {
    foreach ($line in $Lines) { if ($line -notmatch $Pattern) { $line } }
}

# /regex/i\text
function Add-LineBefore($Lines, [string]$Pattern, [string]$Text) {
    foreach ($line in $Lines) { if ($line -cmatch $Pattern) { $Text }; $line }
}

# sed range /start/,/end/: the end is looked for from the line after the start; -Delete drops the lines, otherwise Pattern/Replacement apply in it
function Edit-Range($Lines, [string]$Start, [string]$End, [switch]$Delete, [string]$Pattern, [string]$Replacement) {
    $inRange = $false
    foreach ($line in $Lines) {
        $member = $false
        if ($inRange) { $member = $true; if ($line -cmatch $End) { $inRange = $false } }
        elseif ($line -cmatch $Start) { $member = $true; $inRange = $true }
        if (-not $member) { $line }
        elseif (-not $Delete) { ([regex]$Pattern).Replace($line, $Replacement, 1) }
    }
}

# ---- OpenResty: the Windows build has no forwarded-header variables, no dhparam, no QUIC, local log and html folders
$proxy = Join-Path $Nginx 'onlyoffice-proxy.conf'
$proxyTemplate = Join-Path $Nginx 'onlyoffice-proxy.conf.tmpl'
$proxySsl = Join-Path $Nginx 'onlyoffice-proxy-ssl.conf.tmpl'
$portal = Join-Path $Nginx 'onlyoffice.conf'
Edit-Files @($proxy, $proxyTemplate, $proxySsl) { param($l) Set-Text $l 'this_host|proxy_x_forwarded_host' 'host' -All }
Edit-Files @($proxy, $proxyTemplate) { param($l) Set-Text $l 'proxy_x_forwarded_port' 'server_port' -All }
Edit-Files @($proxy, $proxyTemplate, $proxySsl) { param($l) Set-Text $l 'proxy_x_forwarded_proto' 'scheme' -All }
Edit-Files @($proxySsl) { param($l) Set-Text $l 'ssl_dhparam /etc/ssl/certs/dhparam.pem;' '#ssl_dhparam /etc/ssl/certs/dhparam.pem;' }
Edit-Files @($proxySsl) { param($l) Remove-Lines $l '(?i)quic|alt-svc' }
Edit-Files @((Join-Path $Nginx 'includes\letsencrypt.conf')) { param($l) Set-Text $l '(.*root).*;' '$1 "{APPDIR}letsencrypt";' -All }
Edit-Files @($proxy, $proxyTemplate, $proxySsl) { param($l) Set-Text $l '/var/log/nginx/' 'logs/' -All }
Edit-Files @($portal) { param($l) Set-Text $l '/etc/nginx/html' 'conf/html' -All }
Edit-Files @($portal) { param($l) Set-Text $l '/etc/nginx/\.htpasswd_dashboards' '.htpasswd_dashboards' -All }

# ---- Fluent Bit: Windows log paths, a daily exec input that drops OpenSearch log documents older than 30 days, quotes for cmd
$fluentBit = Join-Path $Config 'fluent-bit.conf'
# Backslash paths: the Windows tail input finds no files with / in the path
$text = [IO.File]::ReadAllText($fluentBit).Replace('/var/log/onlyoffice/', '{APPDIR}Logs\').Replace('**/', '**\')
[IO.File]::WriteAllText($fluentBit, $text)
$command = '    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H ''Content-Type: application/json'' -d ''{"query": {"range": {"@timestamp": {"lt": "now-30d"}}}}'''
foreach ($inputLine in '[INPUT]', '    Name                exec', '    Interval_Sec        86400', $command) {
    Edit-Files @($fluentBit) { param($l) Add-LineBefore $l '^\[OUTPUT\]' $inputLine }
}
Edit-Files @($fluentBit) { param($l) foreach ($line in $l) { $line.Replace('"', '\"').Replace("'", '"') } }
Edit-Files @($fluentBit) { param($l) Add-LineBefore $l '^\[OUTPUT\]' '' }

Remove-Item -Path (Join-Path $Config '*.test.json'), (Join-Path $Config '*.dev.json') -Force -ErrorAction SilentlyContinue

# ---- Product configs: version, warning log level, cookies and tokens, production URLs
$appsettings = Join-Path $Config 'appsettings.json'
Edit-Files @($appsettings) { param($l) Set-Text $l '"number": *"[0-9.]*"' ('"number": "' + $Version + '"') }
Edit-Files @($appsettings) { param($l) Set-Text $l '("Default":).*,' '$1 "Warning",' -All }
Edit-Files @((Join-Path $Config 'appsettings.services.json')) { param($l) Set-Text $l '("logLevel":).*' '$1 "warning"' -All }
Edit-Files @($appsettings) { param($l) Edit-Range $l '"debug-info": \{' '\}' -Pattern '("enabled": )".*"' -Replacement '$1"false"' }
Edit-Files @($appsettings) { param($l) Set-Text $l '("samesite":).*,' '$1 "None",' -All }
Edit-Files @($appsettings) { param($l) Set-Text $l '("disableValidateToken":).*,' '$1 "false",' -All }
Edit-Files @($appsettings) { param($l) Set-Text $l '("showPII":).*' '$1 "false"' -All }
Edit-Files @((Join-Path $Config 'autofac.consumers.json')) { param($l) Set-Text $l 'teamlab.info' 'onlyoffice.com' -All -Unless 'weixinRedirectUrl' }
Edit-Files @((Join-Path $FilesDir 'public\scripts\config.json')) { param($l) Set-Text $l '("wrongPortalNameUrl":).*,' '$1 "",' -All }

# ---- NLog: warnings and above (Bug 77834), no AWS targets
$nlog = Join-Path $Config 'nlog.config'
Edit-Files @($nlog) { param($l) Set-Text $l 'minlevel=[^ >]*' 'minlevel="Warn"' -All -Unless 'ZiggyCreatures' }
Edit-Files @($nlog) { param($l) Edit-Range (Edit-Range $l '<target type="AWSTarget" name="aws"' '</target>' -Delete) '<target type="AWSTarget" name="aws_sql"' '</target>' -Delete }

# ---- Portals the Windows installation does not serve, and services its health check must not wait for (Bug 64516)
Remove-Item -LiteralPath (Join-Path $Nginx 'onlyoffice-login.conf'), (Join-Path $Nginx 'onlyoffice-story.conf'), (Join-Path $Nginx 'onlyoffice-management.conf') -Force -ErrorAction SilentlyContinue
$healthChecks = Join-Path $FilesDir 'services\ASC.Web.HealthChecks.UI\service\appsettings.json'
Edit-Files @($healthChecks) { param($l) Edit-Range $l '"Name": "ASC.ApiCache"' '\{' -Delete }
Edit-Files @($healthChecks) { param($l) Edit-Range $l '"Name": "ASC.ApiSystem"' '\{' -Delete }

Write-Host "Configs adapted to Windows in $FilesDir"
