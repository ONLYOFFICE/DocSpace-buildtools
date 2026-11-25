# Keeps one copy of the node_modules packages that the Next.js apps share, in Files\node_modules (APPDIR\node_modules after the install).
# Node.js looks for a module in the node_modules of every parent folder, so the apps find a package there once their own copy is gone.
# A package moves only if it has the same version in every app that has it and all its dependencies move too or are nested in it.
[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$FilesDir,
    [string[]]$Apps = @('products\ASC.Login\login', 'products\ASC.Files\editor', 'products\ASC.Sdk\sdk', 'products\ASC.Management\management')
)

$ErrorActionPreference = 'Stop'
$FilesDir = (Resolve-Path -LiteralPath $FilesDir).ProviderPath.TrimEnd('\')
$SharedDir = Join-Path $FilesDir 'node_modules'

# Top-level packages of one node_modules folder: name -> folder, scoped packages as @scope/name.
function Get-TopPackages([string]$NodeModules) {
    $Result = @{}
    foreach ($Entry in Get-ChildItem -LiteralPath $NodeModules -Directory -Force) {
        if ($Entry.Name.StartsWith('.')) { continue }
        $Folders = if ($Entry.Name.StartsWith('@')) { Get-ChildItem -LiteralPath $Entry.FullName -Directory -Force } else { @($Entry) }
        foreach ($Folder in $Folders) {
            $Name = if ($Entry.Name.StartsWith('@')) { "$($Entry.Name)/$($Folder.Name)" } else { $Folder.Name }
            $Result[$Name] = $Folder.FullName
        }
    }
    return $Result
}

$Inventory = @{}
foreach ($App in $Apps) {
    $NodeModules = Join-Path $FilesDir "$App\node_modules"
    if (-not (Test-Path -LiteralPath $NodeModules)) { throw "$NodeModules does not exist" }
    foreach ($Entry in (Get-TopPackages $NodeModules).GetEnumerator()) {
        $PackageJson = Join-Path $Entry.Value 'package.json'
        $Json = if (Test-Path -LiteralPath $PackageJson) { Get-Content -LiteralPath $PackageJson -Raw | ConvertFrom-Json } else { $null }
        $Version = if ($Json -and $Json.version) { $Json.version } else { '' }
        if (-not $Inventory.ContainsKey($Entry.Key)) { $Inventory[$Entry.Key] = @() }
        $Inventory[$Entry.Key] += [pscustomobject]@{ App = $App; Folder = $Entry.Value; Version = $Version; Json = $Json }
    }
}

$Candidates = New-Object 'System.Collections.Generic.HashSet[string]'
$VersionConflicts = 0
foreach ($Name in $Inventory.Keys) {
    $Versions = @($Inventory[$Name] | Select-Object -ExpandProperty Version -Unique)
    if ($Inventory[$Name].Count -ge 2 -and $Versions.Count -eq 1 -and $Versions[0]) { [void]$Candidates.Add($Name) }
    elseif ($Versions.Count -gt 1) { $VersionConflicts++ }
}

# Drop a candidate whose dependency stays in an app: from Files\node_modules it could not reach that copy. Repeat until stable.
do {
    $Dropped = New-Object System.Collections.Generic.List[string]
    foreach ($Name in @($Candidates)) {
        foreach ($Instance in $Inventory[$Name]) {
            $Dependencies = @()
            foreach ($Field in 'dependencies', 'optionalDependencies', 'peerDependencies') {
                if ($Instance.Json -and $Instance.Json.$Field) { $Dependencies += $Instance.Json.$Field.PSObject.Properties.Name }
            }
            $Blocked = $Dependencies | Where-Object { $_ } | Where-Object {
                -not (Test-Path -LiteralPath (Join-Path $Instance.Folder ('node_modules\' + ($_ -replace '/', '\')))) -and
                -not $Candidates.Contains($_) -and $Inventory.ContainsKey($_)
            } | Select-Object -First 1
            if ($Blocked) { $Dropped.Add($Name); break }
        }
    }
    foreach ($Name in $Dropped) { [void]$Candidates.Remove($Name) }
} while ($Dropped.Count -gt 0)

$KeptFiles = 0; $KeptBytes = 0; $DroppedFiles = 0; $DroppedBytes = 0
foreach ($Name in $Candidates) {
    $Target = Join-Path $SharedDir ($Name -replace '/', '\')
    foreach ($Instance in $Inventory[$Name]) {
        $Root = $Instance.Folder.TrimEnd('\')
        # The apps trace different subsets of one package, so the shared copy is the union of their files.
        foreach ($File in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
            $Destination = Join-Path $Target $File.FullName.Substring($Root.Length + 1)
            if (Test-Path -LiteralPath $Destination) {
                $DroppedFiles++; $DroppedBytes += $File.Length
                continue
            }
            New-Item -ItemType Directory -Force -Path (Split-Path $Destination -Parent) | Out-Null
            Copy-Item -LiteralPath $File.FullName -Destination $Destination
            $KeptFiles++; $KeptBytes += $File.Length
        }
        Remove-Item -LiteralPath $Root -Recurse -Force
        $Scope = Split-Path $Root -Parent
        if ((Split-Path $Scope -Leaf).StartsWith('@') -and -not (Get-ChildItem -LiteralPath $Scope -Force)) { Remove-Item -LiteralPath $Scope -Force }
    }
}
Write-Host ("Shared node_modules: {0} of {1} packages moved, {2} files ({3} MB) kept once, {4} duplicate files ({5} MB) dropped, {6} packages kept per app because of different versions" -f `
    $Candidates.Count, $Inventory.Count, $KeptFiles, [int]($KeptBytes / 1MB), $DroppedFiles, [int]($DroppedBytes / 1MB), $VersionConflicts)
exit 0
