PUSHD %~dp0..

cd client

REM call pnpm wipe

call pnpm install

cd ..

POPD