@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\products\ASC.Files\Service\bin\Debug\ASC.Files.Service.exe urls=http://0.0.0.0:5009 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=files.service pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products core:eventBus:subscriptionClientName=asc_event_bus_files_service_queue
