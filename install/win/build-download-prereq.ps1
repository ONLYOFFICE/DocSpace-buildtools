$AllProtocols = [System.Net.SecurityProtocolType]::Tls -bor `
                [System.Net.SecurityProtocolType]::Tls11 -bor `
                [System.Net.SecurityProtocolType]::Tls12

[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols

# Function 'DownloadComponents' downloads some components that need on build satge
#
# It gets two parameters list of maps and download path
#
# The map consists of: download_allways ($true/$false) - should this component should download every time
#                  name - name of the dowmloaded component
#                  link - component download link

function DownloadComponents {

  param ( $prereq_list, $path )

  [void](New-Item -ItemType Directory -Force -Path $path)
    
  ForEach ( $item in $prereq_list ) {
    $url = $item.link
    $output = $path + $item.name

    try
    {
      if( $item.download_allways ){
        [system.console]::WriteLine("Downloading $url")
        Invoke-WebRequest -Uri $url -OutFile $output
      } else {
        if(![System.IO.File]::Exists($output)){
          [system.console]::WriteLine("Downloading $url")
          Invoke-WebRequest -Uri $url -OutFile $output
        }
      }
    } catch {
      Write-Host "[ERROR] Can not download" $item.name "by link" $url
    }
  }
}

switch ( $env:DOCUMENT_SERVER_VERSION_EE )
{
  latest { $DOCUMENT_SERVER_EE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver-ee.exe" }
  custom { $DOCUMENT_SERVER_EE_LINK = $env:DOCUMENT_SERVER_EE_CUSTOM_LINK.Replace(",", "") }
}

switch ( $env:DOCUMENT_SERVER_VERSION_CE )
{
  latest { $DOCUMENT_SERVER_CE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver.exe" }
  custom { $DOCUMENT_SERVER_CE_LINK = $env:DOCUMENT_SERVER_CE_CUSTOM_LINK.Replace(",", "") }
}

switch ( $env:DOCUMENT_SERVER_VERSION_DE )
{
  latest { $DOCUMENT_SERVER_DE_LINK = "https://download.onlyoffice.com/install/documentserver/windows/onlyoffice-documentserver-de.exe" }
  custom { $DOCUMENT_SERVER_DE_LINK = $env:DOCUMENT_SERVER_DE_CUSTOM_LINK.Replace(",", "") }
}

$psql_version = '14.0'

$path_prereq = "${pwd}\buildtools\install\win\"

$opensearchstack_path = "${pwd}\buildtools\install\win\OpenSearchStack\"

$opensearch_version = '2.18.0'

$opensearchdashboards_version = '2.18.0'

$openresty_version = '1.27.1.1'

$fluentbit_version = '3.2.4'

$opensearchstack_components = @(

  @{
    download_allways = $false;
    name = "opensearch-dashboards-${opensearchdashboards_version}-windows-x64.zip";
    link = "https://artifacts.opensearch.org/releases/bundle/opensearch-dashboards/${opensearchdashboards_version}/opensearch-dashboards-${opensearchdashboards_version}-windows-x64.zip";
  }

  @{
    download_allways = $false;
    name = "fluent-bit-${fluentbit_version}-win64.zip";
    link = "https://packages.fluentbit.io/windows/fluent-bit-${fluentbit_version}-win64.zip";
  }
)

$prerequisites = @(
  
  @{  
    download_allways = $false; 
    name = "nuget.exe"; 
    link = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe";
  }

  @{
    download_allways = $false;
    name = "opensearch-${opensearch_version}.zip";
    link = "https://artifacts.opensearch.org/releases/bundle/opensearch/${opensearch_version}/opensearch-${opensearch_version}-windows-x64.zip";
  }
  
  @{
    download_allways = $false;
    name = "openresty-${openresty_version}.zip";
    link = "https://openresty.org/download/openresty-${openresty_version}-win64.zip";
  }

  @{
    download_allways = $false;
    name = "ingest-attachment-${opensearch_version}.zip";
    link = "https://artifacts.opensearch.org/releases/plugins/ingest-attachment/${opensearch_version}/ingest-attachment-${opensearch_version}.zip";
  }

  @{  
    download_allways = $false; 
    name = "WinSW.NET4new.exe"; 
    link = "https://github.com/winsw/winsw/releases/download/v2.11.0/WinSW.NET4.exe";
  }

   @{  
    # Downloading onlyoffice-documentserver-ee for DocSpace Enterprise
    download_allways = $true; 
    name = "onlyoffice-documentserver-ee.exe"; 
    link = $DOCUMENT_SERVER_EE_LINK
  }

  @{
    # Downloading onlyoffice-documentserver for DocSpace Community
    download_allways = $true; 
    name = "onlyoffice-documentserver.exe"; 
    link = $DOCUMENT_SERVER_CE_LINK
  }
   
   @{  
    # Downloading onlyoffice-documentserver-de for DocSpace Developer
    download_allways = $true; 
    name = "onlyoffice-documentserver-de.exe"; 
    link = $DOCUMENT_SERVER_DE_LINK
  }
)

$path_enterprise_prereq = "${pwd}\buildtools\install\win\redist\"
$aip_path = "${pwd}\buildtools\install\win\DocSpace.aip"

if (Test-Path $aip_path) {
    [xml]$xml = Get-Content -LiteralPath $aip_path -Encoding UTF8
    $re = 'https://[^\s`"''><]+'
    $attrValues = $xml.SelectNodes("//*") | ForEach-Object { $_.Attributes | ForEach-Object { $_.Value } }
    $textValues = $xml.SelectNodes("//*[text()]") | ForEach-Object { $_.InnerText }
    $urls = @($attrValues + $textValues) -match $re | Sort-Object -Unique
    $enterprise_prerequisites = @()
    foreach ($u in $urls) {
        $name = [IO.Path]::GetFileName(([uri]$u).AbsolutePath)
        if (-not $name) { $name = 'download.bin' }
        $enterprise_prerequisites += @{ download_allways = $false; name = $name; link = $u }
  }
}

DownloadComponents $prerequisites $path_prereq

DownloadComponents $enterprise_prerequisites $path_enterprise_prereq

DownloadComponents $opensearchstack_components $opensearchstack_path