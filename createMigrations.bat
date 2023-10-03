@echo "MIGRATIONS"
@echo off

PUSHD %~dp0..\server\common\Tools\ASC.Migration.Creator
dotnet run --project ASC.Migration.Creator.csproj
pause