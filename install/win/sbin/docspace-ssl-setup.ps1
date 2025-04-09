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
        [string]$certFile
    )

    $extension = [System.IO.Path]::GetExtension($certFile).ToLower()
    $pemCertFile = "$($certFile -replace '\.[^.]+$', '.pem')"
    $pemKeyFile = "$($certFile -replace '\.[^.]+$', '-private.pem')"

    switch ($extension) {
        ".pfx" {
            Write-Output "Detected PFX certificate, converting to PEM..."
            try {
                $password = Read-Host "Enter password for PFX (press Enter if none)" -AsSecureString
                $plainPassword = [System.Net.NetworkCredential]::new("", $password).Password
                openssl pkcs12 -in "$certFile" -out "$pemCertFile" -nokeys -passin pass:"$plainPassword"
                openssl pkcs12 -in "$certFile" -out "$pemKeyFile" -nocerts -nodes -passin pass:"$plainPassword"
            } catch {
                Write-Output "Failed to convert PFX. Check password or file integrity."
                exit 1
            }
        }
        ".der" {
            Write-Output "Detected DER certificate, converting to PEM..."
            openssl x509 -inform DER -in "$certFile" -out "$pemCertFile"
        }
        ".cer" {
            Write-Output "Detected CER certificate, converting to PEM..."
            openssl x509 -inform DER -in "$certFile" -out "$pemCertFile"
        }
        ".p7b" {
            Write-Output "Detected PKCS#7 certificate, converting to PEM..."
            openssl pkcs7 -print_certs -in "$certFile" -out "$pemCertFile"
        }
        default {
            Write-Output "No conversion needed or unsupported format: $certFile"
        }
    }
    return @{
        CertFile = $pemCertFile
        KeyFile = $pemKeyFile
    }
}

function CheckFileFormat {
    param (
        [string]$filePath
    )

    if (!(Test-Path $filePath)) {
        Write-Output "Error: File not found - $filePath"
        exit 1
    }

    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
    switch ($extension) {
        ".pfx" { return "PFX" }
        ".der" { return "DER" }
        ".cer" { return "CER" }
        ".p7b" { return "PKCS7" }
		".pem" { return "PEM" }
    }
    Write-Output "Unsupported or invalid file format: $filePath"
    exit 1
}

if ( $args.Count -ge 2 )
{

  if ($args[0] -eq "-f") {
    $letsencrypt_domain = $args[1] -JOIN ","
    $ssl_cert = $args[2]
    $ssl_key = $args[3]
    $certFormat = CheckFileFormat -filePath $ssl_cert
     if ($certFormat -ne "PEM") {
         Write-Output "Detected $certFormat certificate, converting to PEM..."
         $pemFiles = ConvertToPem -certFile $ssl_cert
         $ssl_cert = $pemFiles.CertFile
         $ssl_key = $pemFiles.KeyFile
     }
  }

  else {
    $letsencrypt_mail = $args[0] -JOIN ","
    $letsencrypt_domain = $args[1] -JOIN ","

    [void](New-Item -ItemType "directory" -Path "${root_dir}\Logs" -Force)

    "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-start.log"
    cmd.exe /c "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-new.log"

    pushd "${letsencrypt_root_dir}\${product}"
        $ssl_cert = (Get-Item "${letsencrypt_root_dir}\${product}\fullchain.pem").FullName.Replace('\', '/')
        $ssl_key = (Get-Item "${letsencrypt_root_dir}\${product}\privkey.pem").FullName.Replace('\', '/')
    popd
  }

  if ( [System.IO.File]::Exists($ssl_cert) -and [System.IO.File]::Exists($ssl_key) -and [System.IO.File]::Exists("${nginx_conf_dir}\${nginx_ssl_tmpl}"))
  {
    Copy-Item "${nginx_conf_dir}\${nginx_ssl_tmpl}" -Destination "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${app}\config\appsettings.$environment.json" -Raw) -replace '"portal":\s*"[^"]*"', "`"portal`": `"https://$letsencrypt_domain`"") | Set-Content -Path "${app}\config\appsettings.$environment.json"
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/usr/local/share/ca-certificates/tls.crt', "`"$ssl_cert`"") | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/etc/ssl/private/tls.key', "`"$ssl_key`"") | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"

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

elseif ($args[0] -eq "-d" -or $args[0] -eq "--default") {
    Copy-Item "${nginx_conf_dir}\${nginx_conf_tmpl}" -Destination "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${app}\config\appsettings.$environment.json" -Raw) -replace '"portal":\s*"[^"]*"', '"portal": "http://localhost:80"') | Set-Content -Path "${app}\config\appsettings.$environment.json"
    [System.Environment]::SetEnvironmentVariable("NODE_EXTRA_CA_CERTS", $null, "Machine")
    foreach ($service in $node_services) { Restart-Service -Name $service }
    Restart-Service -Name $proxy_service
    Remove-Item -Path "${app}\letsencrypt\letsencrypt_cron.bat" -Force
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
