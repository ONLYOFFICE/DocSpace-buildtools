# Stage 7: downloads Docs, nuget.exe and the OpenSearch/OpenResty archives into out\downloads, the payload of the Prerequisites EXE into
# out\redist and the OpenSearchStack archives; writes the Docs Community version and the Docs arguments (docs-secret-args.ps1) into Apps.aip.
# Docs comes from DOCUMENT_SERVER_VERSION_CE|EE|DE: 'latest' or 'custom' with DOCUMENT_SERVER_CE|EE|DE_CUSTOM_LINK.
. "$PSScriptRoot\lib\common.ps1"
$Versions = & "$PSScriptRoot\versions.ps1"

# Windows PowerShell 5.1 does not enable TLS 1.2 by default
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Returns the size the server reports for a download, or nothing when it does not report one
function Get-RemoteSize([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -Method Head -UseBasicParsing -TimeoutSec 60
        $length = 0L
        if ([long]::TryParse("$($response.Headers['Content-Length'])", [ref]$length) -and $length -gt 0) { return $length }
    } catch { }
}

# Downloads each @{ Name; Link; Always } into Folder: Always (Docs) every build, the rest when missing or of a different size
function Save-Downloads([object[]]$Items, [string]$Folder) {
    New-Folder $Folder
    foreach ($item in $Items) {
        $output = Join-Path $Folder $item.Name
        $partial = "$output.partial"
        try {
            $download = $item.Always -or -not (Test-Path -LiteralPath $output)
            if (-not $download) {
                # A build stopped during a download leaves a partial file, so a file whose size differs from the server's is downloaded again
                $remote = Get-RemoteSize $item.Link
                $local = (Get-Item -LiteralPath $output).Length
                if ($remote -and $remote -ne $local) { Write-Host "$($item.Name) has $local bytes instead of $remote"; $download = $true }
            }
            if ($download) {
                Write-Host "Downloading $($item.Link)"
                # The file gets its name only when complete, so an interrupted download is never taken for a finished one
                try { Invoke-WebRequest -Uri $item.Link -OutFile $partial -UseBasicParsing }
                catch { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue; throw }
                Move-Item -LiteralPath $partial -Destination $output -Force
            }
        }
        catch {
            Write-Host "[ERROR] Can not download $($item.Name) by link $($item.Link): $($_.Exception.Message)"
            if ($item.Name -like 'onlyoffice-documentserver*.exe') { throw }
        }
    }
}

# Docs of each edition: the newest published one, or a link given to the build
function Get-DocsLink([string]$Edition, [string]$File) {
    $mode = [Environment]::GetEnvironmentVariable("DOCUMENT_SERVER_VERSION_$Edition")
    if ($mode -eq 'custom') { return "$([Environment]::GetEnvironmentVariable("DOCUMENT_SERVER_${Edition}_CUSTOM_LINK"))".Replace(',', '') }
    return "https://download.onlyoffice.com/install/documentserver/windows/$File"
}

$opensearch = $Versions.OpenSearch
$openresty = $Versions.OpenResty
$dashboards = $Versions.OpenSearchDashboards
$fluentBit = $Versions.FluentBit
$downloads = @(
    @{ Name = 'nuget.exe'; Link = 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' }
    @{ Name = "opensearch-$opensearch.zip"; Link = "https://artifacts.opensearch.org/releases/bundle/opensearch/$opensearch/opensearch-$opensearch-windows-x64.zip" }
    @{ Name = "openresty-$openresty.zip"; Link = "https://openresty.org/download/openresty-$openresty-win64.zip" }
    @{ Name = "ingest-attachment-$opensearch.zip"; Link = "https://artifacts.opensearch.org/releases/plugins/ingest-attachment/$opensearch/ingest-attachment-$opensearch.zip" }
    @{ Name = 'onlyoffice-documentserver-ee.exe'; Link = (Get-DocsLink 'EE' 'onlyoffice-documentserver-ee.exe'); Always = $true }
    @{ Name = 'onlyoffice-documentserver.exe'; Link = (Get-DocsLink 'CE' 'onlyoffice-documentserver.exe'); Always = $true }
    @{ Name = 'onlyoffice-documentserver-de.exe'; Link = (Get-DocsLink 'DE' 'onlyoffice-documentserver-de.exe'); Always = $true }
)
$stack = @(
    @{ Name = "opensearch-dashboards-$dashboards-windows-x64.zip"; Link = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/$dashboards/opensearch-dashboards-$dashboards-windows-x64.zip" }
    @{ Name = "fluent-bit-$fluentBit-win64.zip"; Link = "https://packages.fluentbit.io/windows/fluent-bit-$fluentBit-win64.zip" }
)

# The Prerequisites EXE embeds every https:// link of Apps.aip
$aip = Join-Path $Paths.Installer 'Apps.aip'
[xml]$xml = Get-Content -LiteralPath $aip -Encoding UTF8
$values = @($xml.SelectNodes('//*') | ForEach-Object { $_.Attributes | ForEach-Object { $_.Value } }) + @($xml.SelectNodes('//*[text()]') | ForEach-Object { $_.InnerText })
$redist = foreach ($url in (@($values) -match 'https://[^\s`"''><]+' | Sort-Object -Unique)) {
    $name = [IO.Path]::GetFileName(([uri]$url).AbsolutePath)
    if (-not $name) { $name = 'download.bin' }
    @{ Name = $name; Link = $url }
}

Save-Downloads $downloads $Paths.Downloads

# The Docs Community version goes into DS_VERSION and into the minimum version of the Docs search
$docsInstaller = Join-Path $Paths.Downloads 'onlyoffice-documentserver.exe'
$docsVersion = (Get-Item -LiteralPath $docsInstaller).VersionInfo.ProductVersion.Trim()
if ($docsVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "Invalid Docs Community version '$docsVersion' in $docsInstaller" }
$project = [IO.File]::ReadAllText($aip)
$versionProperty = '(<ROW Property="DS_VERSION" Value=")[^"]*'
$communitySearch = '(<ROW SearchKey="ONLYOFFICEDocumentServer_is1"[^\r\n]*? VerMin=")[^"]*'
if ([regex]::Matches($project, $versionProperty).Count -ne 1 -or [regex]::Matches($project, $communitySearch).Count -ne 1) {
    throw 'Unable to find the Docs Community version fields in Apps.aip'
}
$project = [regex]::Replace([regex]::Replace($project, $versionProperty, '${1}' + $docsVersion), $communitySearch, '${1}' + $docsVersion)
([xml]$project) | Out-Null
[IO.File]::WriteAllText($aip, $project, (New-Object Text.UTF8Encoding($false)))
Write-Host "Docs Community version in Apps.aip: $docsVersion"
& (Join-Path $Paths.Lib 'docs-secret-args.ps1') -AipPath $aip -DocsDir $Paths.Downloads

Save-Downloads @($redist) (Join-Path $Paths.Out 'redist')
Save-Downloads $stack (Join-Path $Paths.Out 'OpenSearchStack')

# Every file the later stages pack: the downloads, the Prerequisites payload and the OpenSearchStack archives
$out = 'buildtools\install\win\out'
$prerequisites = [IO.File]::ReadAllText((Join-Path $Paths.Installer 'Apps.Prerequisites.aip'))
$payload = [regex]::Matches($prerequisites, 'SetupFileUrl="\.\.\\out\\(redist\\[^"]+)"') | ForEach-Object { "$out\$($_.Groups[1].Value)" }
Assert-Paths 'download' (@($downloads | ForEach-Object { "$out\downloads\$($_.Name)" }) + @($stack | ForEach-Object { "$out\OpenSearchStack\$($_.Name)" }) + @($payload))
