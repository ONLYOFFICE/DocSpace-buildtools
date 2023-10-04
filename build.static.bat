@echo off

for %%i in ("%~dp0..") do set "parentFolder=%%~fi"

cd /D "%~dp0"
call runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
PUSHD %~dp0..

IF "%2"=="personal" (
   echo "mode=%2"
) ELSE (
   echo "mode="
)

cd client

REM call yarn wipe
call yarn install

REM call yarn build
IF "%2"=="personal" (
    call yarn build:personal
) ELSE (
    call yarn build
)

REM call yarn wipe
IF "%2"=="personal" (
    call yarn deploy:personal
) ELSE (
    call yarn deploy
)

cd ..

REM copy nginx configurations to deploy folder
xcopy buildtools\config\nginx\onlyoffice.conf publish\nginx\ /E /R /Y
powershell -Command "(gc publish\nginx\onlyoffice.conf) -replace '#', '' | Out-File -encoding ASCII publish\nginx\onlyoffice.conf"

xcopy buildtools\config\nginx\sites-enabled\* publish\nginx\sites-enabled\ /E /R /Y

REM fix paths
powershell -Command "(gc publish\nginx\sites-enabled\onlyoffice-client.conf) -replace 'ROOTPATH', '%parentFolder%\publish\web\client' -replace '\\', '/' | Out-File -encoding ASCII publish\nginx\sites-enabled\onlyoffice-client.conf"

REM restart nginx
echo service nginx stop
call sc stop nginx > nul

REM sleep 5 seconds
call ping 127.0.0.1 -n 6 > nul

echo service nginx start
call sc start nginx > nul

if NOT %errorlevel% == 0 (
	echo Couldn't restart Onlyoffice%%~nf service			
)

)

echo.

POPD

if "%1"=="nopause" goto start
pause
:start