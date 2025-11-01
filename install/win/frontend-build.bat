@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

%sed% -i "s/^; node-linker=hoisted/node-linker=hoisted/" client\.npmrc

pushd %~s1

  call pnpm install

  call pnpm run deploy

popd
