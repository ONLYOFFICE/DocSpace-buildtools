@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\web\ASC.Web.Studio\bin\Debug\ASC.Web.Studio.exe urls=http://0.0.0.0:5003 $STORAGE_ROOT=%cd%\Data  log:dir=%cd%\Logs log:name=web.studio pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products