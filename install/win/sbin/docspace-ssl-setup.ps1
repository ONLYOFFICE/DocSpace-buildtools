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
        [string]$filePath
    )

    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()

    switch ($extension) {
        ".pfx" {
            Write-Output "Converting PFX to PEM..."
            $pemCertFile = "$($filePath -replace '\.pfx$', '.pem')"
            $pemKeyFile = "$($filePath -replace '\.pfx$', '-private.pem')"

            $pfx = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
            try {
                $pfx.Import($filePath, $null, "Exportable, PersistKeySet")
            } catch {
                $password = Read-Host "Enter password for PFX" -AsSecureString
                try {
                    $pfx.Import($filePath, $password, "Exportable, PersistKeySet")
                } catch {
                    Write-Output "Invalid password or corrupt PFX file"
                    exit 1
                }
            }

            $pemCert = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($pfx.RawData, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----"
            $pemCert | Set-Content -Path $pemCertFile -Encoding Ascii

            $privateKey = $pfx.PrivateKey
            if ($privateKey) {
                $pemKey = "-----BEGIN PRIVATE KEY-----`n" + [Convert]::ToBase64String($privateKey.ExportPkcs8PrivateKey(), 'InsertLineBreaks') + "`n-----END PRIVATE KEY-----"
                $pemKey | Set-Content -Path $pemKeyFile -Encoding Ascii
            } else {
                Write-Output "No private key found in PFX"
            }

            return @{"CertFile" = $pemCertFile; "KeyFile" = $pemKeyFile}
        }

        ".der" { 
            Write-Output "Converting DER to PEM..."
            $pemCertFile = "$($filePath -replace '\.der$', '.pem')"
            $DerBytes = [System.IO.File]::ReadAllBytes($filePath)
            $PemCert = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($DerBytes, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----"
            $PemCert | Set-Content -Path $pemCertFile -Encoding Ascii
            return @{"CertFile" = $pemCertFile}
        }

        ".cer" {
            Write-Output "Converting CER to PEM..."
            $pemCertFile = "$($filePath -replace '\.cer$', '.pem')"
            $CerBytes = [System.IO.File]::ReadAllBytes($filePath)
            $PemCert = "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($CerBytes, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----"
            $PemCert | Set-Content -Path $pemCertFile -Encoding Ascii
            return @{"CertFile" = $pemCertFile}
        }

        ".p7b" { 
            Write-Output "Converting PKCS#7 (P7B) to PEM..."
            $pemCertFile = "$($filePath -replace '\.p7b$', '.pem')"
            $CertCollection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $CertCollection.Import($filePath)

            $PemCerts = ""
            foreach ($Cert in $CertCollection) {
                $PemCerts += "-----BEGIN CERTIFICATE-----`n" + [Convert]::ToBase64String($Cert.RawData, 'InsertLineBreaks') + "`n-----END CERTIFICATE-----`n"
            }
            $PemCerts | Set-Content -Path $pemCertFile -Encoding Ascii
            return @{"CertFile" = $pemCertFile}
        }

        default {
            Write-Output "Unsupported file format: $filePath"
            exit 1
        }
    }
}

function CheckFileFormat {
    param (
        [string]$filePath
    )

    if (!(Test-Path $filePath)) {
        Write-Output "File not found - $filePath"
        exit 1
    }

    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()

    if ($extension -in @(".pfx", ".der", ".cer", ".p7b", ".p7c")) {
        Write-Output "Detected format: $extension"
        return $extension
    }

    $content = Get-Content -Path $filePath -Raw
    if ($content -match "-----BEGIN CERTIFICATE-----") {
        Write-Output "PEM format detected."
        return "PEM"
    }

    Write-Output "Unsupported or invalid file format: $filePath"
    exit 1
}


if ($args.Count -ge 2) {
    if ($args[0] -eq "-f") {
        $letsencrypt_domain = $args[1] -JOIN ","
        $ssl_cert = $args[2]
        $ssl_key = $args[3]

        $certFormat = CheckFileFormat -filePath $ssl_cert

        if ($certFormat -in @(".pfx", ".der", ".cer", ".p7b")) {
            Write-Output "Detected $certFormat certificate, converting to PEM..."
            $pemFiles = ConvertToPem -filePath $ssl_cert
            $ssl_cert = $pemFiles.CertFile
            if ($pemFiles.ContainsKey("KeyFile")) {
                $ssl_key = $pemFiles.KeyFile
            }
        }
    }
}

  else {
    $letsencrypt_mail = $args[0] -JOIN ","
    $letsencrypt_domain = $args[1] -JOIN ","

    [void](New-Item -ItemType "directory" -Path "${root_dir}\Logs" -Force)

    "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-start.log"
    cmd.exe /c "certbot certonly --expand --webroot -w `"${root_dir}`" --key-type rsa --cert-name ${product} --noninteractive --agree-tos --email ${letsencrypt_mail} -d ${letsencrypt_domain}" > "${app}\letsencrypt\Logs\le-new.log"

    pushd "${letsencrypt_root_dir}\${product}"
        $ssl_cert = (Resolve-Path -Path (Get-Item "${letsencrypt_root_dir}\${product}\fullchain.pem").Target).ToString().Replace('\', '/')
        $ssl_key = (Resolve-Path -Path (Get-Item "${letsencrypt_root_dir}\${product}\privkey.pem").Target).ToString().Replace('\', '/')
    popd
  }

  if ( [System.IO.File]::Exists($ssl_cert) -and [System.IO.File]::Exists($ssl_key) -and [System.IO.File]::Exists("${nginx_conf_dir}\${nginx_ssl_tmpl}"))
  {
    Copy-Item "${nginx_conf_dir}\${nginx_ssl_tmpl}" -Destination "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${app}\config\appsettings.$environment.json" -Raw) -replace '"portal":\s*"[^"]*"', "`"portal`": `"https://$letsencrypt_domain`"") | Set-Content -Path "${app}\config\appsettings.$environment.json"
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/usr/local/share/ca-certificates/tls.crt', $ssl_cert) | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"
    ((Get-Content -Path "${nginx_conf_dir}\${nginx_conf}" -Raw) -replace '/etc/ssl/private/tls.key', $ssl_key) | Set-Content -Path "${nginx_conf_dir}\${nginx_conf}"

    if ($letsencrypt_domain -and (Test-Path $letsencrypt_domain_dir))
    {
        $acl = Get-Acl -Path $letsencrypt_domain_dir
        $acl.SetSecurityDescriptorSddlForm('O:LAG:S-1-5-21-4011186057-2202358572-2315966083-513D:PAI(A;;0x1200a9;;;WD)(A;;FA;;;SY)(A;OI;0x1200a9;;;LS)(A;;FA;;;BA)(A;;FA;;;LA)')
        Set-Acl -Path $acl.path -ACLObject $acl
    }

    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($ssl_cert)

    if ($cert.Subject -eq $cert.Issuer) {
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
  Write-Output "    CERTIFICATE   Path to the certificate file for the domain."
  Write-Output "    PRIVATEKEY    Path to the private key file for the certificate."
  Write-Output "                                                                   "
  Write-Output " Return to the default proxy configuration using the -d or --default parameter: "
  Write-Output "  docspace-ssl-setup.ps1 -d | docspace-ssl-setup.ps1 --default  "
}
