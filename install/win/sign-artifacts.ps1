$workerCount = 4
$workingDirectory = (Get-Location).Path
$folderPath = Join-Path $workingDirectory "buildtools\install\win\Files"
$signScript = Join-Path $workingDirectory "buildtools\install\win\signing-tool.ps1"

if (-not (Test-Path -LiteralPath $signScript -PathType Leaf)) {
    throw "Signing script not found: $signScript"
}

$files = @(Get-ChildItem -Path $folderPath -Recurse -File -ErrorAction Stop |
    Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object { $_.FullName })

Write-Host "Signing $($files.Count) files with $workerCount workers."

$signFiles = {
    param($SignScript, $Files, $WorkingDirectory)

    Set-Location -LiteralPath $WorkingDirectory -ErrorAction Stop
    foreach ($file in $Files) {
        Write-Output "Signing: $file"
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $SignScript -File $file
        if ($LASTEXITCODE -ne 0) {
            throw "Signing failed (exit $LASTEXITCODE): $file"
        }
    }
}

$jobs = for ($workerIndex = 0; $workerIndex -lt $workerCount; $workerIndex++) {
    $workerFiles = @(for ($fileIndex = $workerIndex; $fileIndex -lt $files.Count; $fileIndex += $workerCount) {
        $files[$fileIndex]
    })
    Start-Job -ScriptBlock $signFiles -ArgumentList $signScript, $workerFiles, $workingDirectory -ErrorAction Stop
}

$jobs | Wait-Job | Receive-Job -ErrorAction Continue
$failedJobs = @($jobs | Where-Object { $_.State -ne 'Completed' })
$jobs | Remove-Job

if ($failedJobs.Count -gt 0) {
    throw "Signing failed in $($failedJobs.Count) worker(s)."
}

Write-Host "Signing completed."
