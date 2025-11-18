@echo off

PUSHD %~dp0..\..
set servicepath=%cd%\server\common\services\ASC.TelegramService\bin\Debug\ASC.TelegramService.exe urls=http://0.0.0.0:5075 $STORAGE_ROOT=%cd%\Data log:dir=%cd%\Logs log:name=telegram pathToConf=%cd%\buildtools\config core:products:folder=%cd%\server\products core:eventBus:subscriptionClientName=asc_event_bus_telegram_queue