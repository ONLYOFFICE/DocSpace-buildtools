@echo OFF
REM Check if node is installed
node -v 2> Nul 2>&1
if "%errorlevel%" == "9009" (
    echo Node.js could not be found.
	start https://nodejs.org/en/download/package-manager
	exit /b
)

@echo ON

PUSHD %~dp0\..

set root=%cd%

PUSHD %root%\client\common\tests

set tests=%cd%

call npm install

call npm run test:locales

@Echo off
:: Display date and time independent of OS Locale, Language or date format.
For /f "delims=" %%A in ('powershell get-date -format "{yyyy-MM-dd_HH_mm_ss}"') do @set _isodate=%%A

set OUTPUT=%root%\TestsResults\TestResult__%_isodate%.html

echo f | xcopy %tests%\reports\tests-results.html %OUTPUT% /F /E /R /Y

echo Results saved to: %OUTPUT%

start %OUTPUT%

pause