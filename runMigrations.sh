#!/bin/bash
echo "MIGRATIONS"
echo off

rd="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
echo "Run script directory:" $rd

dir=$(builtin cd $rd/../; pwd)
echo "Root directory:" $dir

dotnet build $dir/server/asc.web.slnf
dotnet build $dir/server/ASC.Migrations.sln

pushd $dir/server/common/Tools/ASC.Migration.Runner/bin/Debug/

dotnet ASC.Migration.Runner.dll
