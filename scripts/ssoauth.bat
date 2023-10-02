PUSHD %~dp0..

cd %~dp0../../server/common/ASC.SsoAuth/

call yarn install --immutable

POPD