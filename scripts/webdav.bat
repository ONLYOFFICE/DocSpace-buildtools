PUSHD %~dp0..

cd %~dp0../../server/common/ASC.WebDav/

call yarn install --immutable

POPD