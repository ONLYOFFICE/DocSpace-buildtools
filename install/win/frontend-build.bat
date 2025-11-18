@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

set DEBUG_INFO=%~2

pushd %~s1

  call pnpm install

  call node common\scripts\before-build.js

  set TS_ERRORS_IGNORE=true

  call pnpm nx build @docspace/client --env lint=false
  call pnpm nx deploy @docspace/client 

  call pnpm nx build @docspace/login
  call pnpm nx deploy @docspace/login

  call pnpm nx build @docspace/doceditor
  call pnpm nx deploy @docspace/doceditor

  call pnpm nx build @docspace/management
  call pnpm nx deploy @docspace/management

  call pnpm nx build @docspace/sdk
  call pnpm nx deploy @docspace/sdk

  xcopy /E /I /Y public "..\publish\web\public\"
  call node common\scripts\minify-common-locales.js

popd
