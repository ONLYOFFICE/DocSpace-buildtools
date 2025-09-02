@echo off

echo [1/4] Building project
start "" /wait build.backend.bat -p:GenerateDocumentationFile=true

echo [2/4] Building openapi Documentation
cd ..\server\common\Tools\ASC.Api.Documentation
dotnet build ASC.Api.Documentation.sln
cd ASC.Api.Documentation\bin\Debug\net8.0
redocly join asc.web.api.swagger.json asc.people.swagger.json asc.files.swagger.json asc.data.backup.swagger.json ..\..\..\..\..\CustomGenerators\tools\oauth.json -o ..\..\..\..\..\CustomGenerators\tools\api-docs.json
cd ..\..\..\..\..\CustomGenerators\tools

echo [3/4] Running sortTagGroups.js to sort tag groups...
node sortTagGroups.js

echo [4/4] Running removeStringEnum.js to clean up string enums...
node removeStringEnum.js

echo [1/6] Building custom generator with Maven...
cd ..
mvn clean package || goto :error
echo Maven build done.

echo [2/6] Generating C# SDK with OpenAPI Generator...
openapi-generator-cli generate -c tools/toolsCSharp.json --custom-generator target/custom-generators-1.0-SNAPSHOT-jar-with-dependencies.jar || goto :error

echo [3/6] Generating Python SDK with OpenAPI Generator...
openapi-generator-cli generate -c tools/toolsPython.json --custom-generator target/custom-generators-1.0-SNAPSHOT-jar-with-dependencies.jar || goto :error

echo [4/6] Generating Postman SDK with OpenAPI Generator...
openapi-generator-cli generate -c tools/toolsPostmanCollection.json --custom-generator target/custom-generators-1.0-SNAPSHOT-jar-with-dependencies.jar || goto :error

echo [5/6] Generating Typescript SDK with OpenAPI Generator...
openapi-generator-cli generate -c tools/toolsTypeScript.json --custom-generator target/custom-generators-1.0-SNAPSHOT-jar-with-dependencies.jar || goto :error
cd typescript-sdk
echo [6/6] npm install in typescript-sdk...
npm install || goto :error
cd ..

echo Succesfully completed
pause
