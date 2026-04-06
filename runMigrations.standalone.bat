@echo "MIGRATIONS"
@echo off

cd /D "%~dp0"
call start\stop.bat nopause
dotnet build ..\server\ASC.Web.slnx
dotnet build ..\server\ASC.Migrations.slnx
PUSHD %~dp0..\server\common\Tools\ASC.Migration.Runner\bin\Debug\
dotnet ASC.Migration.Runner.dll standalone=true
pause