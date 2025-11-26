@echo off
echo 
echo ######################
echo #   build docspace-mcp   #
echo ######################

pushd %~s1

  call pnpm install --frozen-lockfile

  call pnpm build-app

popd
