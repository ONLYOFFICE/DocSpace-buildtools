@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\common\services\ASC.Data.Backup.BackgroundTasks\bin\Debug\ASC.Data.Backup.BackgroundTasks.exe urls=http://0.0.0.0:5032 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=backup.backgroundtasks pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products core:eventBus:subscriptionClientName=asc_event_bus_backup_queue