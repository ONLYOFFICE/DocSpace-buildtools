@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\products\ASC.AI\Service\bin\Debug\ASC.AI.Service.exe urls=http://0.0.0.0:5124 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=ai.service pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products