PUSHD %~dp0..

cd %~dp0../../server/common/ASC.Identity/api/

call mvnw compiler:compile
call mvnw package -Dmaven.test.skip

cd %~dp0../../server/common/ASC.Identity/authorization/

call mvnw compiler:compile
call mvnw package -Dmaven.test.skip

POPD