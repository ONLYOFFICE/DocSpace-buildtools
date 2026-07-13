@echo off

PUSHD %~dp0..
call scripts\runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
	for /R "scripts\units\" %%f in (*.bat) do (
                echo Running service stop and delete "Onlyoffice%%~nf"
		call sc stop "Onlyoffice%%~nf"
		call sc delete "Onlyoffice%%~nf"
	)
	for /R "scripts\units\" %%f in (*.xml) do (
		call install\win\WinSW3.0.0.exe stop %%f
		call install\win\WinSW3.0.0.exe uninstall %%f
	)
)

echo.
pause