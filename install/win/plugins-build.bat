@echo off
echo
echo #####################
echo #   plugins build   #
echo #####################

setlocal enabledelayedexpansion

set FirstArg=%~s1
set SecondArg=%~s2

if defined SecondArg (
	set PathToRepository=%FirstArg%
	set PathToAppFolder=%SecondArg%
) else (
	set PathToRepository=%FirstArg%
	set PathToAppFolder=%FirstArg%\publish
)

for /D %%d in ("%PathToRepository%\*") do (
    if exist "%%d\package.json" (
        echo Processing folder: %%d
        pushd "%%d"
        
        call yarn install
        call yarn run build
        
        popd
        
        set "folderName=%%~nxd"
        set "distDir=%%d\dist"
        set "targetDir=%PathToAppFolder%\!folderName!"
        echo !distDir!
        if exist "!distDir!\plugin.zip" (
            echo Unzipping plugin.zip from !distDir! to !targetDir!
            mkdir "!targetDir!" 2>nul
            %sevenzip% x "!distDir!\plugin.zip" -o"!targetDir!" -y
        ) else (
            echo plugin.zip not found in !distDir!
        )
    )
)

endlocal
