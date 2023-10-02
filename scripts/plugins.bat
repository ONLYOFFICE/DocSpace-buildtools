PUSHD %~dp0..

cd %~dp0../../server/common/ASC.WebPlugins/

call yarn install --immutable

call yarn build

POPD