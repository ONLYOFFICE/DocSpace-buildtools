# Stage 1: builds docspace-mcp into mcp\bin; 8-package.ps1 copies it into products\ASC.AI\mcp.
. "$PSScriptRoot\lib\common.ps1"

Push-Location -LiteralPath (Join-Path $Paths.Work 'mcp')
try {
    Invoke-Tool 'pnpm' @('install', '--frozen-lockfile')
    Invoke-Tool 'pnpm' @('build-app')
}
finally { Pop-Location }
Assert-Paths 'mcp' @('mcp\bin\*')
