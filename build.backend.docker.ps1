param(
  [switch] $h = $false,
  [switch] $f = $false,
  [switch] $s = $true,
  [switch] $c = $false,
  [switch] $d = $false
)

if ($h) {
  Write-Host "Build and run backend and working environment. (Use 'yarn start' to run client -> https://github.com/ONLYOFFICE/DocSpace-client)"
  Write-Host
  Write-Host "Syntax: available params [-h|f|s|c|d|]"
  Write-Host "Options:"
  Write-Host "h     Print this Help."
  Write-Host "f     Force rebuild base images."
  Write-Host "s     Run as SAAS otherwise as STANDALONE."
  Write-Host "c     Run as COMMUNITY otherwise ENTERPRISE."
  Write-Host "d     Run dnsmasq."
  Write-Host
  exit
}

$PSversionMajor = $PSVersionTable.PSVersion | sort-object major | ForEach-Object { $_.major }
$PSversionMinor = $PSVersionTable.PSVersion | sort-object minor | ForEach-Object { $_.minor }

if ($PSversionMajor -lt 7 -or $PSversionMinor -lt 2) {
  Write-Error "Powershell version must be greater than or equal to 7.2."
  exit
}

$RootDir = Split-Path -Parent $PSScriptRoot
$DockerDir = "$RootDir\buildtools\install\docker"
$LocalIp = (Get-CimInstance -ClassName Win32_NetworkAdapterConfiguration | Where-Object { $_.DHCPEnabled -ne $null -and $_.DefaultIPGateway -ne $null }).IPAddress | Select-Object -First 1

$Doceditor = ($LocalIp + ":5013")
$Login = ($LocalIp + ":5011")
$Client = ($LocalIp + ":5001")
$PortalUrl = ("http://" + $LocalIp)
$ProxyVersion="v1.0.0"

# Stop all backend services"
& "$PSScriptRoot\start\stop.backend.docker.ps1"

$Env:COMPOSE_IGNORE_ORPHANS = "True"

$ExistsNetwork= docker network ls --format '{{.Name}}' | findstr "onlyoffice" 

if (-not $ExistsNetwork) {
  docker network create --driver bridge onlyoffice
}

Write-Host "Run MySQL" -ForegroundColor Green
docker compose -f "$DockerDir\db.yml" up -d

if ($d) {
  Write-Host "Run local dns server" -ForegroundColor Green
  $Env:ROOT_DIR=$RootDir
  docker compose -f "$DockerDir\dnsmasq.yml" up -d
}

Write-Host "Build backend services (to `publish/` folder)" -ForegroundColor Green
& "$PSScriptRoot\install\common\build-services.ps1"

$Env:DOCUMENT_SERVER_IMAGE_NAME = "onlyoffice/documentserver-de:latest"
$Env:INSTALLATION_TYPE = "ENTERPRISE"
$Env:MIGRATION_TYPE = "STANDALONE"

if ($c) {
  $Env:DOCUMENT_SERVER_IMAGE_NAME = "onlyoffice/documentserver:latest"
  $Env:INSTALLATION_TYPE = "COMMUNITY"
}

if (-not $s) {
  $Env:MIGRATION_TYPE = "SAAS"
}

Set-Location -Path $RootDir

$DotnetVersion = "dev"
$NodeVersion = "dev"
$ProxyVersion = "dev"

$ExistsDotnet= docker images --format "{{.Repository}}:{{.Tag}}" | findstr "onlyoffice/4testing-docspace-dotnet-runtime:$DotnetVersion"
$ExistsNode= docker images --format "{{.Repository}}:{{.Tag}}" | findstr "onlyoffice/4testing-docspace-nodejs-runtime:$NodeVersion"
$ExistsProxy= docker images --format "{{.Repository}}:{{.Tag}}" | findstr "onlyoffice/4testing-docspace-proxy-runtime:$ProxyVersion"

if (!$ExistsDotnet -or $f) {
  Write-Host "Build dotnet base image from source (apply new dotnet config)" -ForegroundColor Green
  docker build -t "onlyoffice/4testing-docspace-dotnet-runtime:$DotnetVersion"  -f "$DockerDir\Dockerfile.runtime" --target dotnetrun .
} else { 
  Write-Host "SKIP build dotnet base image (already exists)" -ForegroundColor Blue
}

if (!$ExistsNode -or $f) {
  Write-Host "Build node base image from source" -ForegroundColor Green
  docker build -t "onlyoffice/4testing-docspace-nodejs-runtime:$NodeVersion"  -f "$DockerDir\Dockerfile.runtime" --target noderun .
} else { 
  Write-Host "SKIP build node base image (already exists)" -ForegroundColor Blue
}

if (!$ExistsProxy -or $f) {
  Write-Host "Build proxy base image from source (apply new nginx config)" -ForegroundColor Green
  docker build -t "onlyoffice/4testing-docspace-proxy-runtime:$ProxyVersion"  -f "$DockerDir\Dockerfile.runtime" --target router .
} else { 
  Write-Host "SKIP build proxy base image (already exists)" -ForegroundColor Blue
}

Write-Host "Run migration and services" -ForegroundColor Green
$Env:ENV_EXTENSION="dev"
$Env:Baseimage_Dotnet_Run="onlyoffice/4testing-docspace-dotnet-runtime:$DotnetVersion"
$Env:Baseimage_Nodejs_Run="onlyoffice/4testing-docspace-nodejs-runtime:$NodeVersion"
$Env:Baseimage_Proxy_Run="onlyoffice/4testing-docspace-proxy-runtime:$ProxyVersion"
$Env:SERVICE_DOCEDITOR=$Doceditor
$Env:SERVICE_LOGIN=$Login
$Env:SERVICE_CLIENT=$Client
$Env:ROOT_DIR=$RootDir
$Env:BUILD_PATH="/var/www"
$Env:SRC_PATH="$RootDir\publish\services"
$Env:DATA_DIR="$RootDir\data"
$Env:APP_URL_PORTAL=$PortalUrl
docker compose -f "$DockerDir\docspace.profiles.yml" -f "$DockerDir\docspace.overcome.yml" --profile migration-runner --profile backend-local up -d

Write-Host "Run OAuth2" -ForegroundColor Green
$Env:DOCSPACE_ADDRESS=$LocalIp
docker compose -f "$DockerDir\oauth2.yml" up -d

Write-Host "== Build params ==" -ForegroundColor Green
Write-Host "APP_URL_PORTAL: $PortalUrl" -ForegroundColor Blue
Write-Host "LOCAL IP: $LocalIp" -ForegroundColor Blue
Write-Host "SERVICE_DOCEDITOR: $Env:SERVICE_DOCEDITOR" -ForegroundColor Blue
Write-Host "SERVICE_LOGIN: $Env:SERVICE_LOGIN" -ForegroundColor Blue
Write-Host "SERVICE_CLIENT: $Env:SERVICE_CLIENT" -ForegroundColor Blue
Write-Host "INSTALLATION_TYPE: $Env:INSTALLATION_TYPE" -ForegroundColor Blue
Write-Host "MIGRATION TYPE: $Env:MIGRATION_TYPE" -ForegroundColor Blue
Write-Host "DS IMAGE: $Env:DOCUMENT_SERVER_IMAGE_NAME" -ForegroundColor Blue

Set-Location -Path $PSScriptRoot