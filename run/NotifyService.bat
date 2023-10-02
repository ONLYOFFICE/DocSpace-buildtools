@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\common\services\ASC.Notify\bin\Debug\ASC.Notify.exe urls=http://0.0.0.0:5005 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=notify pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products core:eventBus:subscriptionClientName=asc_event_bus_notify_queue