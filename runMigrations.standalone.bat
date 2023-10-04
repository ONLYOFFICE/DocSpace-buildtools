@echo "MIGRATIONS"
@echo off

cd /D "%~dp0"
call start\stop.bat nopause
dotnet build ..\server\asc.web.slnf
dotnet build ..\server\ASC.Migrations.sln
PUSHD %~dp0..\server\common\Tools\ASC.Migration.Runner\bin\Debug\net7.0
dotnet ASC.Migration.Runner.dll standalone=true
pause