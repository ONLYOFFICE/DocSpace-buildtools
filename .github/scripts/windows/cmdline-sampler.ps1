# Records every distinct process command line about once a second into -Out until -StopFile appears; started by install-exe.ps1.
# The file may hold secrets: keep it outside the uploaded folders; checklist.ps1 checks and deletes it.
param(
    [Parameter(Mandatory)][string]$Out,
    [Parameter(Mandatory)][string]$StopFile,
    [int]$MaxHours = 4
)
$ErrorActionPreference = 'SilentlyContinue'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$deadline = (Get-Date).AddHours($MaxHours)
$writer = New-Object IO.StreamWriter($Out, $true, (New-Object Text.UTF8Encoding($false)))
try {
    while (-not (Test-Path -LiteralPath $StopFile) -and (Get-Date) -lt $deadline) {
        foreach ($process in Get-CimInstance Win32_Process -Property Name, CommandLine) {
            if (-not $process.CommandLine) { continue }
            $line = "$($process.Name)`t$($process.CommandLine)"
            if ($seen.Add($line)) { $writer.WriteLine($line); $writer.Flush() }
        }
        Start-Sleep -Milliseconds 700
    }
} finally { $writer.Dispose() }
