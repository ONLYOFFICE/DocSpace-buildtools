# Docs 10.0.3+ reads its secrets from the Apps registry key or a parameters file; older Docs keeps the /JWT_SECRET and /DB_PWD arguments.
param(
  [Parameter(Mandatory = $true)][string]$AipPath,
  [Parameter(Mandatory = $true)][string]$DocsDir
)

$ErrorActionPreference = 'Stop'
$MinVersion = [version]'10.0.3'
$LegacyJwt = ' /JWT_SECRET=&quot;[DOCUMENT_SERVER_JWT_SECRET]&quot;'
$LegacyDbPwd = ' /DB_PWD=&quot;[PS_DB_PWD]&quot;'
$SecureArgs = ' /APPS_REGISTRY_KEY=&quot;Software\[Manufacturer]\[ShortProductName]&quot; /PARAMS_FILE=&quot;[DOCS_PARAMS_FILE]&quot;'
$Installers = [ordered]@{
  'DocumentServer'    = 'onlyoffice-documentserver.exe'
  'DocumentServer.EE' = 'onlyoffice-documentserver-ee.exe'
  'DocumentServer.DE' = 'onlyoffice-documentserver-de.exe'
}

$Project = [IO.File]::ReadAllText($AipPath)
foreach ($Key in $Installers.Keys) {
  $Installer = Join-Path $DocsDir $Installers[$Key]
  $Version = [version](Get-Item -LiteralPath $Installer).VersionInfo.ProductVersion.Trim()
  # Advanced Installer 22.3 writes the key in upper case when it saves the project (DOCUMENTSERVER)
  $Rows = [regex]::Matches($Project, '<ROW PrereqKey="' + [regex]::Escape($Key) + '"[^>]*/>', 'IgnoreCase')
  if ($Rows.Count -ne 1) { throw "Prerequisite row $Key not found in $AipPath" }
  $Row = $Rows[0].Value
  $NewRow = $Row
  if ($Version -ge $MinVersion) {
    $NewRow = $NewRow.Replace($LegacyJwt, '').Replace($LegacyDbPwd, $SecureArgs)
    if ($NewRow.Contains('[DOCUMENT_SERVER_JWT_SECRET]') -or $NewRow.Contains('[PS_DB_PWD]')) { throw "Unexpected command line in $Key" }
  }
  elseif (-not $Row.Contains($LegacyDbPwd)) {
    throw "$Key bundles Docs $Version, which needs the /JWT_SECRET and /DB_PWD arguments, but the row no longer has them"
  }
  $Project = $Project.Replace($Row, $NewRow)
  Write-Host ("Docs {0} in {1}: secrets {2}" -f $Version, $Key, $(if ($Version -ge $MinVersion) { 'from the Apps registry key or a parameters file' } else { 'on the command line' }))
}
$Xml = New-Object Xml.XmlDocument
$Xml.LoadXml($Project)
[IO.File]::WriteAllText($AipPath, $Project, (New-Object Text.UTF8Encoding($false)))
