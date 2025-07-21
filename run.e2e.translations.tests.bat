@echo off

PUSHD %~dp0
call runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
PUSHD %~dp0..


echo "mode="


REM call pnpm wipe
call pnpm install

REM call pnpm build
call pnpm build:test.translation

REM call pnpm wipe
call pnpm deploy


REM copy nginx configurations to deploy folder
xcopy config\nginx\onlyoffice.conf buildtools\deploy\nginx\ /E /R /Y
powershell -Command "(gc buildtools\deploy\nginx\onlyoffice.conf) -replace '#', '' | Out-File -encoding ASCII buildtools\deploy\nginx\onlyoffice.conf"

xcopy config\nginx\sites-enabled\* buildtools\deploy\nginx\sites-enabled\ /E /R /Y

REM fix paths
powershell -Command "(gc buildtools\deploy\nginx\sites-enabled\onlyoffice-editor.conf) -replace 'ROOTPATH', '%~dp0deploy\products\ASC.Files\editor' -replace '\\', '/' | Out-File -encoding ASCII buildtools\deploy\nginx\sites-enabled\onlyoffice-editor.conf"
powershell -Command "(gc buildtools\deploy\nginx\sites-enabled\onlyoffice-login.conf) -replace 'ROOTPATH', '%~dp0deploy\login' -replace '\\', '/' | Out-File -encoding ASCII buildtools\deploy\nginx\sites-enabled\onlyoffice-login.conf"
powershell -Command "(gc buildtools\deploy\nginx\sites-enabled\onlyoffice-client.conf) -replace 'ROOTPATH', '%~dp0deploy\client' -replace '\\', '/' | Out-File -encoding ASCII buildtools\deploy\nginx\sites-enabled\onlyoffice-client.conf"

REM restart nginx
echo service nginx stop
call sc stop nginx > nul

REM sleep 5 seconds
call ping 127.0.0.1 -n 6 > nul

echo service nginx start
call sc start nginx > nul

REM sleep 5 seconds
call ping 127.0.0.1 -n 6 > nul

call pnpm e2e.test:translation

exit



if NOT %errorlevel% == 0 (
	echo Couldn't restarte Onlyoffice%%~nf service			
)

)

echo.

POPD

if "%1"=="nopause" goto start
pause
:start
