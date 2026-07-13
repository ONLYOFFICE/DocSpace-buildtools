@echo off

chcp 65001 > nul

PUSHD %~dp0..
call scripts\runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
	PUSHD %~dp0..\..
	setlocal EnableDelayedExpansion
	for /R "buildtools\scripts\units\windows\" %%f in (*.bat) do (
		call "%%f"
		echo service create "Onlyoffice%%~nf"
		call sc create "Onlyoffice%%~nf" displayname= "ONLYOFFICE %%~nf" binPath= "!servicepath!"
	)
	for /R "buildtools\scripts\units\windows\" %%f in (*.xml) do (
		call buildtools\install\win\WinSW3.0.0.exe install %%f
	)
)

echo.
pause
