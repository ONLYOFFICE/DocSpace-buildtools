@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

%sed% -i "s/^# *nodeLinker: *hoisted/nodeLinker: hoisted/" client\pnpm-workspace.yaml

pushd %~s1

  call pnpm install

  call pnpm run deploy

popd
