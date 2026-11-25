# Stage 3: builds DocSpace-client into publish\web; the Jenkins job may set NODE_OPTIONS and "parallel": 1 in client\nx.json for low memory.
. "$PSScriptRoot\lib\common.ps1"

$client = Join-Path $Paths.Work 'client'
# A hoisted node_modules, as the Windows package copies the apps with their own node_modules
Update-TextFile (Join-Path $client 'pnpm-workspace.yaml') '(?m)^# *nodeLinker: *hoisted' 'nodeLinker: hoisted'

Push-Location -LiteralPath $client
try {
    Invoke-Tool 'pnpm' @('install')
    Invoke-Tool 'pnpm' @('run', 'deploy')
}
finally { Pop-Location }
Assert-Paths 'frontend' @('publish\web\public\*', 'publish\web\client\*', 'publish\web\login\*', 'publish\web\editor\*', 'publish\web\sdk\*', 'publish\web\management\*')
