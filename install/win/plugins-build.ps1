param($FirstArg, $SecondArg)

$repo = $FirstArg
$app = if ($SecondArg) { $SecondArg } else { "$FirstArg\publish" }

Get-ChildItem $repo -Directory | ForEach-Object {
    $pkg = "$($_.FullName)\package.json"
    if (Test-Path $pkg) {
        Write-Host "Building $($_.Name)"
        Push-Location $_.FullName
        yarn install; yarn run build
        Pop-Location

        $name = (Get-Content $pkg | ConvertFrom-Json).name
        $zip = "$($_.FullName)\dist\plugin.zip"
        $target = "$app\$name"
	
	Write-Host "SevenZip path: $env:sevenzip"
	Test-Path $env:sevenzip

        if (Test-Path $zip) {
            New-Item -ItemType Directory -Force -Path $target | Out-Null
            & $env:sevenzip x "$zip" "-o$target" -y
        } else {
            Write-Host "plugin.zip not found in $($_.Name)"
        }
    }
}
