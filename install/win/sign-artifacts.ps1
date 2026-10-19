$folderPath = Join-Path (Get-Location) "buildtools\install\win\Files"
$signScript = Join-Path (Get-Location) "buildtools\install\win\signing-tool.ps1"

Write-Host "Folder path: $folderPath"
Write-Host "Sign script: $signScript"

if (-not (Test-Path $signScript)) {
    throw "Sign.ps1 not found: $signScript"
}

$files = Get-ChildItem -Path $folderPath -Recurse -File |
    Where-Object { $_.Extension -in '.exe', '.dll' }

Write-Host "Found files count: $($files.Count)"

foreach ($file in $files) {
    Write-Host "Signing: $($file.FullName)"
    & $signScript -File $file.FullName
}

Write-Host "Signing completed."
