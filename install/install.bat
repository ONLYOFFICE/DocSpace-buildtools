@echo off

PUSHD %~dp0..
call runasadmin.bat "%~dpnx0"

if %errorlevel% == 0 (
	PUSHD %~dp0..\..
	setlocal EnableDelayedExpansion
	for /R "buildtools\run\" %%f in (*.bat) do (
		call buildtools\run\%%~nxf
		echo service create "Onlyoffice%%~nf"
		call sc create "Onlyoffice%%~nf" displayname= "ONLYOFFICE %%~nf" binPath= "!servicepath!"
	)
	for /R "buildtools\run\" %%f in (*.xml) do (
		call buildtools\install\win\WinSW3.0.0.exe install %%f
	)
)

echo.
pause
