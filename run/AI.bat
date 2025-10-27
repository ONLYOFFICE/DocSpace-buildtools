@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\products\ASC.AI\Server\bin\Debug\ASC.AI.exe urls=http://0.0.0.0:5157 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=ai pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products