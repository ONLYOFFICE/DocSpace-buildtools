# Stage 4: production node_modules of the node services and the Identity jars of DocSpace-server.
# The .NET services and the migration runner are built once in Release by 5-publish.ps1.
. "$PSScriptRoot\lib\common.ps1"

$common = Join-Path $Paths.Work 'server\common'
foreach ($service in 'ASC.Socket.IO', 'ASC.AI.Chat', 'ASC.SsoAuth') {
    Push-Location -LiteralPath (Join-Path $common $service)
    try {
        # The lockfile is checked first, then the development dependencies are dropped
        Invoke-Tool 'yarn' @('install', '--frozen-lockfile') "yarn install ($service)"
        Invoke-Tool 'yarn' @('workspaces', 'focus', '--production') "yarn workspaces focus --production ($service)"
    }
    finally { Pop-Location }
}

Push-Location -LiteralPath (Join-Path $common 'ASC.Identity')
try {
    Invoke-Tool 'mvn' @('clean', 'package', '-DskipTests', '-pl', 'authorization/authorization-container', '-am') 'mvn package (Identity authorization)'
    Invoke-Tool 'mvn' @('clean', 'package', '-DskipTests', '-pl', 'registration/registration-container', '-am') 'mvn package (Identity registration)'
}
finally { Pop-Location }
Assert-Paths 'backend' @('server\common\ASC.Socket.IO\node_modules', 'server\common\ASC.AI.Chat\node_modules', 'server\common\ASC.SsoAuth\node_modules',
    'server\common\ASC.Identity\authorization\authorization-container\target\*.jar', 'server\common\ASC.Identity\registration\registration-container\target\*.jar')
