# runas administrator
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
  Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
  exit
}

function Test-RegistryValue($RegistryKey, $RegistryName)
{
  $exists = Get-ItemProperty -Path "$RegistryKey" -Name "$RegistryName" -ErrorAction SilentlyContinue
  if (($exists -ne $null) -and ($exists.Length -ne 0)) { return $true }
  return $false
}

$certbot_path = if ((Test-RegistryValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Certbot" "InstallLocation") -eq $true )
{
  (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Certbot" -ErrorAction Stop).InstallLocation
}
elseif ((Test-RegistryValue "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Certbot" "InstallLocation") -eq $true )
{
  (Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Certbot" -ErrorAction Stop).InstallLocation
}

if ( -not $certbot_path )
{
  Write-Output " Attention! Certbot is not installed on your computer. "
  Write-Output " Certbot could be downloaded by this link 'https://github.com/certbot/certbot/releases/latest/download/certbot-beta-installer-win_amd64_signed.exe' "
  exit
}

$openssl_path = Get-Command openssl -ErrorAction SilentlyContinue

if ( -not $openssl_path )
{
  Write-Output " Attention! OpenSSL is not accessible on your computer. "
  Write-Output " OpenSSL could be downloaded by this link 'https://download.firedaemon.com/FireDaemon-OpenSSL/FireDaemon-OpenSSL-x64-3.3.0.exe' "
  exit
}

$product = "docspace"
$letsencrypt_root_dir = "$env:SystemDrive\Certbot\live"
$letsencrypt_domain_dir = "$env:SystemDrive\Certbot\archive\${product}"
$app = Resolve-Path -Path ".\..\"
$root_dir = "${app}\letsencrypt"
$environment = "production"
$nginx_conf_dir = "$env:SystemDrive\OpenResty\conf"
$nginx_conf = "onlyoffice-proxy.conf"
$nginx_conf_tmpl = "onlyoffice-proxy.conf.tmpl"
$nginx_ssl_tmpl = "onlyoffice-proxy-ssl.conf.tmpl"
$proxy_service = "OpenResty"
$node_services = @(
    "DocSpace.DocEditor",
    "DocSpace.Login",
    "DocSpace.Socket.IO",
    "DocSpace.SsoAuth.Svc",
    "DsDocServiceSvc",
    "DsConverterSvc"
)

function ConvertToPem {
  param (
    [string]$certFile,
    [string]$PfxPassword = ""
  )

  if (-not (Test-Path $certFile)) {
    throw "File not found: $certFile"
  }

  $certFormat = $null
  $certOut    = $null
  $keyOut     = $null

  & openssl pkcs12 -in $certFile -info -noout -passin "pass:$PfxPassword" *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    $certFormat = "PFX"
    $baseName   = [System.IO.Path]::GetFileNameWithoutExtension($certFile)
    $dir        = [System.IO.Path]::GetDirectoryName($certFile)
    $certOut    = Join-Path $dir "$baseName.pem"
    $keyOut     = Join-Path $dir "$baseName-private.pem"
    Write-Host "$certFile is a valid PFX certificate. Converting to PEM..."

    & openssl pkcs12 -in $certFile -out $certOut -nokeys -passin "pass:$PfxPassword"
    & openssl pkcs12 -in $certFile -out $keyOut -nocerts -nodes -passin "pass:$PfxPassword"

    return @{ CertFile = $certOut; KeyFile = $keyOut; Format = $certFormat }
  }

  & openssl x509 -in $certFile -inform PEM -text -noout *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Host "$certFile is a valid PEM certificate."
    return @{ CertFile = $certFile; KeyFile = $null; Format = "PEM" }
  }

  & openssl pkey -in $certFile -check *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    Write-Host "$certFile is a valid private key."
    return @{ CertFile = $null; KeyFile = $certFile; Format = "KEY" }
  }

  & openssl x509 -in $certFile -inform DER -text -noout *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    $certOut = [System.IO.Path]::ChangeExtension($certFile, ".pem")
    Write-Host "$certFile is a valid DER/CER certificate. Converting to PEM..."
    & openssl x509 -in $certFile -inform DER -out $certOut
    return @{ CertFile = $certOut; KeyFile = $null; Format = "DER" }
  }

  & openssl pkcs7 -in $certFile -print_certs -noout *> $null 2>&1
  if ($LASTEXITCODE -eq 0) {
    $certOut = [System.IO.Path]::ChangeExtension($certFile, ".pem")
    Write-Host "$certFile is a valid PKCS#7 certificate. Converting to PEM..."
    & openssl pkcs7 -in $certFile -print_certs -out $certOut
    return @{ CertFile = $certOut; KeyFile = $null; Format = "PKCS7" }
  }

  throw "Unsupported or invalid file format: $certFile"
}

if ( $args.Count -ge 2 ) {
  if ($args[0] -eq "-f" -or $args[0] -eq "--file") {
    $domain_name = $args[1] -join ","
    $ssl_cert           = $args[2]
    $ssl_key            = $null

    if ($args.Count -ge 4) {
      $ssl_key = $args[3]
    }

    $PfxPassword = ""
    if ($ssl_cert -match '\.(p12|pfx)$') {
      Write-Host "Using PKCS#12 file for SSL configuration..."

      & openssl pkcs12 -in $ssl_cert -info -noout -passin "pass:" *> $null 2>&1
      if ($LASTEXITCODE -ne 0) {
        $securePassword = Read-Host -AsSecureString "Enter password"
        $BSTR           = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
        $PfxPassword    = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
      }
    }

    try {
      $conversionResult = ConvertToPem -certFile $ssl_cert -PfxPassword $PfxPassword

      if ($conversionResult.Format -ne "PEM" -and $conversionResult.CertFile) {
        Write-Host "Detected $($conversionResult.Format) certificate, converting to PEM..."
        $ssl_cert = $conversionResult.CertFile
      }

      if ($args.Count -ge 4) {
        $keyCheck = ConvertToPem -certFile $ssl_key
        if ($keyCheck.Format -ne "KEY") {
          throw "The provided file $ssl_key is not a valid private key."
        }
        $ssl_key = $keyCheck.KeyFile
      }

    } catch {
      Write-Error $_.Exception.Message
      exit 1
    }
  }

  else {
    $letsencrypt_mail = $args[0] -JOIN ","
    $letsencrypt_domain = $args[1] -JOIN ","
    $domain_name = $letsencrypt_domain -split ',' | Select-Object -First 1

    [void](New-Item -ItemType "directory" -Path "${root_dir}\Logs" -Force)

    "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-start.log"
    cmd.exe /c "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-new.log"

    pushd "${letsencrypt_root_dir}\${product}"
        $ssl_cert = (Get-Item "${letsencrypt_root_dir}\${product}\fullchain.pem").FullName.Replace('\', '/')
        $ssl_key = (Get-Item "${letsencrypt_root_dir}\${product}\privkey.pem").FullName.Replace('\', '/')
    popd

    @(
        "certbot renew >> `"${app}\letsencrypt\Logs\le-renew.log`"",
        "net stop $proxy_service",
        "net start $proxy_service"
    ) | Set-Content -Path "${app}\letsencrypt\letsencrypt_cron.bat" -Encoding ascii

    $day = (Get-Date -Format "dddd").ToUpper().SubString(0, 3)
    $time = Get-Date -Format "HH:mm"
    $taskName = "Certbot renew"
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"${app}\letsencrypt\letsencrypt_cron.bat`""
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $day -At $time

    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Force
  }

  if ( [System.IO.File]::Exists($ssl_cert) -and [System.IO.File]::Exists($ssl_key) -and [System.IO.File]::Exists("${nginx_conf_dir}\${nginx_ssl_tmpl}"))
  {
    Copy-Item "${nginx_conf_dir}\${nginx_ssl_tmpl}" -Destination "${nginx_conf_dir}\${nginx_conf}"
    if ($domain_name -ne "localhost:80") { ((Get-Content -Path "${app}\config\appsettings.$environment.json" -Raw) -replace '"portal":\s*"[^"]*"', "`"portal`": `"https://$domain_name`"") | Set-Content -Path "${app}\config\appsettings.$environment.json" }
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/usr/local/share/ca-certificates/tls.crt', "`"$ssl_cert`"") | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/etc/ssl/private/tls.key', "`"$ssl_key`"") | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"

    Set-ItemProperty -Path "HKLM:\SOFTWARE\Wow6432Node\Ascensio System SIA\ONLYOFFICE DocSpace" -Name "DOMAIN_NAME" -Value $domain_name

    if ($letsencrypt_domain -and (Test-Path $letsencrypt_domain_dir))
    {
        $acl = Get-Acl -Path $letsencrypt_domain_dir
        $acl.SetSecurityDescriptorSddlForm('O:LAG:S-1-5-21-4011186057-2202358572-2315966083-513D:PAI(A;;0x1200a9;;;WD)(A;;FA;;;SY)(A;OI;0x1200a9;;;LS)(A;;FA;;;BA)(A;;FA;;;LA)')
        Set-Acl -Path $acl.path -ACLObject $acl
    }

	$subject = (& openssl x509 -in $ssl_cert -noout -subject) -replace '^subject= *', ''
	$issuer  = (& openssl x509 -in $ssl_cert -noout -issuer)  -replace '^issuer= *', ''

    if ($subject -eq $issuer) {
        [System.Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $ssl_cert, [System.EnvironmentVariableTarget]::Machine)
        foreach ($service in $node_services) { Restart-Service -Name $service }
    }
  }

  Restart-Service -Name $proxy_service
}

elseif ($args[0] -eq "-d" -or $args[0] -eq "--default") {
    Copy-Item "${nginx_conf_dir}\${nginx_conf_tmpl}" -Destination "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${app}\config\appsettings.$environment.json" -Raw) -replace '"portal":\s*"[^"]*"', '"portal": "http://localhost:80"') | Set-Content -Path "${app}\config\appsettings.$environment.json"
    [System.Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $null, "Machine")
    foreach ($service in $node_services) { Restart-Service -Name $service }
    Restart-Service -Name $proxy_service
    if (Test-Path "${app}\letsencrypt\letsencrypt_cron.bat") { Remove-Item -Path "${app}\letsencrypt\letsencrypt_cron.bat" -Force }
    Write-Host "Returned to the default proxy configuration."
}

else
{
  Write-Output " This script provided to automatically get Let's Encrypt SSL Certificates for DocSpace "
  Write-Output " usage: "
  Write-Output "   docspace-ssl-setup.ps1 EMAIL DOMAIN "
  Write-Output "      EMAIL       Email used for registration and recovery contact. Use "
  Write-Output "                  comma to register multiple emails, ex: "
  Write-Output "                  u1@example.com,u2@example.com. "
  Write-Output "      DOMAIN      Domain name to apply "
  Write-Output "                  Use comma to register multiple domains, ex: "
  Write-Output "                  example.com,s1.example.com,s2.example.com. "
  Write-Output " "
  Write-Output " Using your own certificates via the -f parameter: "
  Write-Output " usage: "
  Write-Output "  docspace-ssl-setup.ps1 -f DOMAIN CERTIFICATE PRIVATEKEY "
  Write-Output "    DOMAIN        Domain name to apply."
  Write-Output "    CERTIFICATE   Path to the certificate file for the domain (PEM, PFX, DER, CER, PKCS#7)."
  Write-Output "    PRIVATEKEY    (Optional) Path to private key (required unless PFX)."
  Write-Output "                                                                   "
  Write-Output " Return to the default proxy configuration using the -d or --default parameter: "
  Write-Output "  docspace-ssl-setup.ps1 -d | docspace-ssl-setup.ps1 --default  "
}
