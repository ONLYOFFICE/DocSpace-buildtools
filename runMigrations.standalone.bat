@echo "MIGRATIONS"
@echo off

cd /D "%~dp0"
call start\stop.bat nopause
dotnet build ..\server\ASC.Web.slnx
dotnet build ..\server\ASC.Migrations.slnx
PUSHD %~dp0..\server\common\Tools\ASC.Migration.Runner\bin\Debug\
dotnet ASC.Migration.Runner.dll standalone=true "options:Providers:0:ConnectionString=Server=localhost;Database=onlyoffice_apps;User ID=dev;Password=dev;Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;AllowPublicKeyRetrieval=True;Connection Timeout=30;Maximum Pool Size=300;ConnectionReset=false;Command Timeout=0" "options:TeamlabsiteProviders:0:ConnectionString=Server=localhost;Database=teamlabsite;User ID=dev;Password=dev;Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;AllowPublicKeyRetrieval=True;Connection Timeout=30;Maximum Pool Size=300;ConnectionReset=false;Command Timeout=0"
pause