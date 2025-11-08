# Path to signtool
$signtool = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe"

# Path to folder
$folderPath = Join-Path (Get-Location) "buildtools\install\win\Files"
$timestampUrl = "http://timestamp.digicert.com"

Write-Host "Folder path: $folderPath"

# Find files
$files = Get-ChildItem -Path $folderPath -Recurse -File | Where-Object { $_.Extension -in '.exe','.dll','.pdb' }
Write-Host "Found files count: $($files.Count)"

foreach ($file in $files) {
    Write-Host "Signing: $($file.FullName)"
    & "$signtool" sign /f "$env:onlyoffice_codesign_path" /p "$env:onlyoffice_codesign_password" /tr "$timestampUrl" /td SHA256 /fd SHA256 "$($file.FullName)" | Out-Null
}

Write-Host "Signing completed."
