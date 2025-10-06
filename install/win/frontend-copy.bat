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

robocopy "%PathToRepository%\publish\web\public" "%PathToAppFolder%\public" /E /COPYALL /R:1 /W:1
robocopy "%PathToRepository%\campaigns\src\campaigns" "%PathToAppFolder%\public\campaigns" /E /COPYALL /R:1 /W:1
robocopy "%PathToRepository%\publish\web\management" "%PathToAppFolder%\management" /E /COPYALL /R:1 /W:1
robocopy "%PathToRepository%\publish\web\client" "%PathToAppFolder%\client" /E /COPYALL /R:1 /W:1
robocopy "%PathToRepository%\buildtools\config\nginx" "%PathToAppFolder%\nginx\conf" /E /COPYALL /R:1 /W:1
robocopy "%PathToRepository%\buildtools\config\*" "%PathToAppFolder%\config" /E /COPYALL /R:1 /W:1
