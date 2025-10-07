@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

set DEBUG_INFO=%~2

pushd %~s1

  call pnpm install

  set TS_ERRORS_IGNORE=true

  call pnpm build
  call pnpm run deploy

popd
