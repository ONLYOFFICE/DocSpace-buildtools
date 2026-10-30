@echo off

echo "##########################################################"
echo "#########  Start build and deploy  #######################"
echo "##########################################################"

echo.

cd /D "%~dp0.."
call tools\runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (


echo "FRONT-END static"
call build\build.static.bat nopause

echo "BACK-END"
call build\build.backend.bat nopause

echo.

pause

)
