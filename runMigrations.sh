#!/bin/bash
echo "MIGRATIONS"
echo off

rd="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "Run script directory:" $rd

dir=$(builtin cd $rd/../; pwd)
echo "Root directory:" $dir

dotnet build $dir/server/ASC.Web.slnx
dotnet build $dir/server/ASC.Migrations.slnx

pushd $dir/server/common/Tools/ASC.Migration.Runner/bin/Debug/

dotnet ASC.Migration.Runner.dll "options:Providers:0:ConnectionString=Server=localhost;Database=onlyoffice_apps;User ID=dev;Password=dev;Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;AllowPublicKeyRetrieval=True;Connection Timeout=30;Maximum Pool Size=300;ConnectionReset=false;Command Timeout=0" "options:TeamlabsiteProviders:0:ConnectionString=Server=localhost;Database=teamlabsite;User ID=dev;Password=dev;Pooling=true;Character Set=utf8;AutoEnlist=false;SSL Mode=none;AllowPublicKeyRetrieval=True;Connection Timeout=30;Maximum Pool Size=300;ConnectionReset=false;Command Timeout=0"
