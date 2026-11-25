# Stage 6: the client, the campaign pages, the configs and the nginx configs into out\Files.
. "$PSScriptRoot\lib\common.ps1"

$web = Join-Path $Paths.Work 'publish\web'
$config = Join-Path $Paths.BuildTools 'config'
$files = $Paths.Files

Copy-Tree (Join-Path $web 'public') (Join-Path $files 'public')
Copy-Tree (Join-Path $Paths.Work 'campaigns\src\campaigns') (Join-Path $files 'public\campaigns')
Copy-Tree (Join-Path $web 'client') (Join-Path $files 'client')
Copy-Tree (Join-Path $config 'nginx') (Join-Path $files 'nginx\conf')
# The top level of config only; document-formats is a submodule with its own files
Copy-Tree (Join-Path $config '*') (Join-Path $files 'config') -Flat
Copy-Tree (Join-Path $config 'document-formats') (Join-Path $files 'config\document-formats') -Flat

Assert-Paths 'copy' @('buildtools\install\win\out\Files\public\*', 'buildtools\install\win\out\Files\public\campaigns\*', 'buildtools\install\win\out\Files\client\*',
    'buildtools\install\win\out\Files\config\appsettings.json', 'buildtools\install\win\out\Files\config\document-formats\*', 'buildtools\install\win\out\Files\nginx\conf\onlyoffice.conf')
