@echo off

for %%i in ("%~dp0..") do set "parentFolder=%%~fi"

cd /D "%~dp0"
call runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
PUSHD %~dp0..

cd client

REM call pnpm install
call pnpm install

REM call yarn wipe
call pnpm run build

cd ..

REM copy nginx configurations to deploy folder
xcopy buildtools\config\nginx\onlyoffice.conf publish\nginx\ /E /R /Y
powershell -Command "(gc publish\nginx\onlyoffice.conf) -replace '#', '' | Out-File -encoding ASCII publish\nginx\onlyoffice.conf"

xcopy buildtools\config\nginx\sites-enabled\* publish\nginx\sites-enabled\ /E /R /Y
xcopy buildtools\config\nginx\includes\* publish\nginx\includes\ /E /R /Y

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