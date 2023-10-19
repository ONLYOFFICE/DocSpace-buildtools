PUSHD %~dp0..

cd %~dp0../../server/common/ASC.OAuth/api/

call mvnw compiler:compile
call mvnw package -Dmaven.test.skip

cd %~dp0../../server/common/ASC.OAuth/authorization/

call mvnw compiler:compile
call mvnw package -Dmaven.test.skip

POPD