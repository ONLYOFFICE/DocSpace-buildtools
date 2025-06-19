@echo off

for %%i in ("%~dp0..") do set "parentFolder=%%~fi"

cd /D "%~dp0"
call runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
PUSHD %~dp0..

cd client

REM call pnpm install
call pnpm install

REM call pnpm deploy (build will be called when necessary)
call pnpm run deploy

cd ..

REM copy nginx configurations to deploy folder
xcopy buildtools\config\nginx\onlyoffice.conf publish\nginx\ /E /R /Y

xcopy buildtools\config\nginx\sites-enabled\* publish\nginx\sites-enabled\ /E /R /Y
xcopy buildtools\config\nginx\html\* publish\nginx\html\ /E /R /Y

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