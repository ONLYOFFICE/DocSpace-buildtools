PUSHD %~dp0..

cd %~dp0../../server/common/ASC.Identity/

echo Start build ASC.Identity project...
echo.

echo ASC.Identity: resolves all project dependencies...
echo.

call mvn dependency:go-offline -q

if %errorlevel% == 0 (

echo ASC.Identity: take the compiled code and package it in its distributable format, such as a JAR...
call mvn package -DskipTests -q

)

if %errorlevel% == 0 (

echo ASC.Identity: build completed
echo.

)


POPD