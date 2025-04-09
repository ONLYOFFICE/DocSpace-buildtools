@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

set DEBUG_INFO=%~2

pushd %~s1

  call yarn install
  if "%DEBUG_INFO%"=="true" yarn debug-info

  call node common\scripts\before-build.js

  set TS_ERRORS_IGNORE=true

  call yarn workspace @docspace/client build --env lint=false
  call yarn workspace @docspace/client deploy

  call yarn workspace @docspace/management build --env lint=false
  call yarn workspace @docspace/management deploy

  call yarn workspace @docspace/login build
  call yarn workspace @docspace/login deploy

  call yarn workspace @docspace/doceditor build
  call yarn workspace @docspace/doceditor deploy

  xcopy /E /I /Y public "..\publish\web\public\"
  call node common\scripts\minify-common-locales.js

popd
