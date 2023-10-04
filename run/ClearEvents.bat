@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\common\services\ASC.ClearEvents\bin\Debug\ASC.ClearEvents.exe urls=http://0.0.0.0:5027 $STORAGE_ROOT=%cd%\Data pathToConf=%cd%\buildtools\config log:dir=%cd%\Logs log:name=clearEvents core:products:folder=%cd%\server\products