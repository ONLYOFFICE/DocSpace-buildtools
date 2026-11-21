@echo off
echo 
echo #####################
echo #  publish backend  #
echo #####################

set FirstArg=%~s1

set SecondArg=%~s2

if defined SecondArg (
	set PathToRepository=%FirstArg%
	set PathToAppFolder=%SecondArg%
) else (
	set PathToRepository=%FirstArg%
	set PathToAppFolder=%FirstArg%\publish
)

rem backend services (dotnet): one Release publish of the solution, as in install/common/packages-build.sh
rem ReleaseProfile puts every service into <repository>\..\publish\services\<name>\service
set "PUBLISH_ARGS=-c Release -r win-x64 --self-contained false -p:DebugType=None -p:DebugSymbols=false"
set "DotnetPublishDir=%PathToRepository%\..\publish\services"
if exist "%DotnetPublishDir%" rmdir /s /q "%DotnetPublishDir%"

dotnet publish "%PathToRepository%\common\Tools\ASC.Migration.Runner\ASC.Migration.Runner.csproj" %PUBLISH_ARGS% -o "%PathToAppFolder%\services\ASC.Migration.Runner\service" || exit /b 1
dotnet publish "%PathToRepository%\ASC.Web.slnx" %PUBLISH_ARGS% -p:PublishProfile=ReleaseProfile || exit /b 1

rem backend services (dotnet) in directory 'products'
call :move_service ASC.Files products\ASC.Files\server || exit /b 1
call :move_service ASC.People products\ASC.People\server || exit /b 1
call :move_service ASC.AI products\ASC.AI\server || exit /b 1
call :move_service ASC.AI.Worker products\ASC.AI\service || exit /b 1

rem backend services (dotnet) in directory 'services'
call :move_service ASC.ApiSystem services\ASC.ApiSystem\service || exit /b 1
call :move_service ASC.Data.Backup services\ASC.Data.Backup\service || exit /b 1
call :move_service ASC.Files.Worker services\ASC.Files.Worker\service || exit /b 1
call :move_service ASC.Notify services\ASC.Notify\service || exit /b 1
call :move_service ASC.Studio.Notify services\ASC.Studio.Notify\service || exit /b 1
call :move_service ASC.Data.Backup.Worker services\ASC.Data.Backup.Worker\service || exit /b 1
call :move_service ASC.TelegramService services\ASC.TelegramService\service || exit /b 1
call :move_service ASC.ClearEvents services\ASC.ClearEvents\service || exit /b 1
call :move_service ASC.Web.Api services\ASC.Web.Api\service || exit /b 1
call :move_service ASC.Web.Studio services\ASC.Web.Studio\service || exit /b 1
call :move_service ASC.Web.HealthChecks.UI services\ASC.Web.HealthChecks.UI\service || exit /b 1

rem backend services (Nodejs) in directory 'services'
mkdir "%PathToAppFolder%\services\ASC.Socket.IO\service"
xcopy "%PathToRepository%\common\ASC.Socket.IO" "%PathToAppFolder%\services\ASC.Socket.IO\service" /s /y /b /i

mkdir "%PathToAppFolder%\services\ASC.AI.Chat\service"
xcopy "%PathToRepository%\common\ASC.AI.Chat" "%PathToAppFolder%\services\ASC.AI.Chat\service" /s /y /b /i

mkdir "%PathToAppFolder%\services\ASC.Files.Worker\service"
xcopy "%PathToRepository%\publish\services\ASC.Files.Worker\service" "%PathToAppFolder%\services\ASC.Files.Worker\service" /s /y /b /i

mkdir "%PathToAppFolder%\services\ASC.SsoAuth\service"
xcopy "%PathToRepository%\common\ASC.SsoAuth" "%PathToAppFolder%\services\ASC.SsoAuth\service" /s /y /b /i

rem backend services (Nodejs) in directory 'products'
mkdir "%PathToAppFolder%\products\ASC.Login\login"
xcopy "%PathToRepository%\..\publish\web\login" "%PathToAppFolder%\products\ASC.Login\login" /s /y /b /i

mkdir "%PathToAppFolder%\products\ASC.Files\editor"
xcopy "%PathToRepository%\..\publish\web\editor" "%PathToAppFolder%\products\ASC.Files\editor" /s /y /b /i

mkdir "%PathToAppFolder%\products\ASC.Sdk\sdk"
xcopy "%PathToRepository%\..\publish\web\sdk" "%PathToAppFolder%\products\ASC.Sdk\sdk" /s /y /b /i

mkdir "%PathToAppFolder%\products\ASC.Management\management"
xcopy "%PathToRepository%\..\publish\web\management" "%PathToAppFolder%\products\ASC.Management\management" /s /y /b /i

rem backend services (Java) in directory 'services'
mkdir "%PathToAppFolder%\services\ASC.Identity.Authorization\service"
for %%f in ("%PathToRepository%\common\ASC.Identity\authorization\authorization-container\target\*.jar") do copy "%%f" "%PathToAppFolder%\services\ASC.Identity.Authorization\service\app.jar" /y

mkdir "%PathToAppFolder%\services\ASC.Identity.Registration\service"
for %%f in ("%PathToRepository%\common\ASC.Identity\registration\registration-container\target\*.jar") do copy "%%f" "%PathToAppFolder%\services\ASC.Identity.Registration\service\app.jar" /y

exit /b 0

rem Move a published service (%1) to its folder in the package (%2); robocopy codes 8 and above are errors
:move_service
robocopy "%DotnetPublishDir%\%~1\service" "%PathToAppFolder%\%~2" /E /MOVE /NFL /NDL /NJH /NJS /NP
if errorlevel 8 (
	echo Error: cannot move the published %~1 to %~2
	exit /b 1
)
exit /b 0

