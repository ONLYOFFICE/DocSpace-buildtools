@echo off

echo "##########################################################"
echo "#########  Start build and deploy  #######################"
echo "##########################################################"

echo.

PUSHD %~dp0..
call tools\runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (

call start\stop.bat nopause

echo "FRONT-END (for start run command 'pnpm start' inside the root folder)"
call build\build.frontend.bat nopause

echo "BACK-END"
call build\build.backend.bat nopause

call start\start.bat nopause

echo.

pause
)