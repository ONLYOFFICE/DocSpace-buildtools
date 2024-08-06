@echo off
echo 
echo #####################
echo #   frontend copy   #
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

xcopy "%PathToRepository%\publish\web\public" "%PathToAppFolder%\public" /s /y /b /i
xcopy "%PathToRepository%\campaigns\src\campaigns" "%PathToAppFolder%\public\campaigns" /s /y /b /i
xcopy "%PathToRepository%\publish\web\management" "%PathToAppFolder%\management" /s /y /b /i
xcopy "%PathToRepository%\publish\web\client" "%PathToAppFolder%\client" /s /y /b /i
xcopy "%PathToRepository%\buildtools\config\nginx" "%PathToAppFolder%\nginx\conf" /s /y /b /i
xcopy "%PathToRepository%\buildtools\config\*" "%PathToAppFolder%\config" /y /b /i
