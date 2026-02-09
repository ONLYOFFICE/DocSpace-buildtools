@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\products\ASC.AI\Worker\bin\Debug\ASC.AI.Worker.exe urls=http://0.0.0.0:5124 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=ai.service pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products