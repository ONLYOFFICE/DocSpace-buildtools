@echo off
echo 
echo ######################
echo #   build frontend   #
echo ######################

REM The node_modules layout is set by `nodeLinker` in the client's
REM pnpm-workspace.yaml. A --node-linker flag does not survive here: pnpm
REM verifies the dependency tree before running a script and relinks it back
REM to the layout declared in the repository.

%sed% -i "s/^# *nodeLinker: *hoisted/nodeLinker: hoisted/" client\pnpm-workspace.yaml

pushd %~s1

  call pnpm install
  if errorlevel 1 goto :fail

  call pnpm run deploy
  if errorlevel 1 goto :fail

popd

exit /b 0

:fail
set BUILD_ERROR=%ERRORLEVEL%
popd
echo Frontend build failed with exit code %BUILD_ERROR%
exit /b %BUILD_ERROR%