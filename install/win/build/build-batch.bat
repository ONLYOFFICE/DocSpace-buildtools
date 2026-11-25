rem Last build stage: prepares out\Files and the auxiliary components, then builds every installer into out\publish.
rem Runs from the workspace root (buildtools, server, plugins, mcp and cloudhsm side by side); see install\win\README.md.
setlocal

REM ######## Set variables ########
set "publisher="Ascensio System SIA""
set "opensearch_version=3.5.0"
set "openresty_version=1.27.1.1"

set "AppsBuildDir=%~dp0"
set "AppsWinDir=buildtools\install\win"
set "AppsInstallerDir=%AppsWinDir%\installer"
set "AppsRuntimeDir=%AppsWinDir%\runtime"
set "AppsOutDir=%AppsWinDir%\out"
set "AppsDownloadsDir=%AppsOutDir%\downloads"
set "AppsFilesDir=%AppsOutDir%\Files"
set "AppsNginxConfDir=%AppsOutDir%\Files\nginx\conf"
set "AppsDockerConfigDir=buildtools\install\docker\config"
set "AppsUtilsDir=%AppsInstallerDir%\CustomActions\C#\Utils"
set "nuget="%cd%\%AppsDownloadsDir%\nuget.exe""
set "AppsServices=Socket.IO AI.Chat SsoAuth DocEditor Login Sdk MCP Management Identity.Authorization Identity.Registration"

REM ######## Extract OpenSearch and OpenResty ########
%sevenzip% x "%AppsDownloadsDir%\opensearch-%opensearch_version%.zip" -o"%AppsOutDir%" -y
%sevenzip% x "%AppsDownloadsDir%\ingest-attachment-%opensearch_version%.zip" -o"%AppsOutDir%\OpenSearch\plugins\ingest-attachment" -y
for %%P in (opensearch-security opensearch-job-scheduler opensearch-index-management opensearch-knn opensearch-neural-search) do (
  xcopy "%AppsOutDir%\opensearch-%opensearch_version%\plugins\%%P" "%AppsOutDir%\OpenSearch\plugins\%%P" /s /y /b /i
)
rmdir "%AppsOutDir%\opensearch-%opensearch_version%\plugins" /s /q
xcopy "%AppsOutDir%\opensearch-%opensearch_version%" "%AppsOutDir%\OpenSearch" /s /y /b /i
rmdir "%AppsOutDir%\opensearch-%opensearch_version%" /s /q
%sevenzip% x "%AppsDownloadsDir%\openresty-%openresty_version%.zip" -o"%AppsOutDir%" -y
xcopy "%AppsOutDir%\openresty-%openresty_version%-win64" "%AppsOutDir%\OpenResty" /s /y /b /i
rmdir "%AppsOutDir%\openresty-%openresty_version%-win64" /s /q

REM ######## Create folders ########
md "%AppsOutDir%\OpenSearch\tools"
md "%AppsOutDir%\OpenResty\tools"
md "%AppsOutDir%\OpenResty\logs"
md "%AppsOutDir%\OpenSearchStack\tools"
for %%D in (tools Logs Data sbin) do md "%AppsFilesDir%\%%D"
for %%D in (products\ASC.Files\server products\ASC.People\server services\ASC.Data.Backup\service services\ASC.Notify\service services\ASC.Files.Worker\service services\ASC.Studio.Notify\service services\ASC.Data.Backup.Worker\service services\ASC.ClearEvents\service services\ASC.ApiSystem\service services\ASC.Web.Api\service services\ASC.Web.Studio\service services\ASC.Web.HealthChecks.UI\service) do (
  md "%AppsFilesDir%\%%D\temp"
)

REM ######## Copy plugins, MCP and the signing tool ########
xcopy "plugins\publish\*" "%AppsFilesDir%\Data\Studio\webplugins" /s /e /y /i
xcopy "mcp\bin\*" "%AppsFilesDir%\products\ASC.AI\mcp" /s /e /y /i
copy cloudhsm\signing-tool.ps1 "%AppsOutDir%\signing-tool.ps1" /y

REM ######## Copy WinSW service wrappers ########
copy "%AppsRuntimeDir%\winsw\WinSW.NET4.exe" "%AppsOutDir%\OpenResty\tools\OpenResty.exe" /y
copy "%AppsRuntimeDir%\winsw\OpenResty.xml" "%AppsOutDir%\OpenResty\tools\OpenResty.xml" /y
copy "%AppsRuntimeDir%\winsw\WinSW3.0.0.exe" "%AppsOutDir%\OpenSearch\tools\OpenSearch.exe" /y
copy "%AppsRuntimeDir%\winsw\OpenSearch.xml" "%AppsOutDir%\OpenSearch\tools\OpenSearch.xml" /y
copy "%AppsRuntimeDir%\winsw\WinSW3.0.0.exe" "%AppsOutDir%\OpenSearchStack\tools\OpenSearchDashboards.exe" /y
copy "%AppsRuntimeDir%\winsw\OpenSearchDashboards.xml" "%AppsOutDir%\OpenSearchStack\tools\OpenSearchDashboards.xml" /y
for %%S in (%AppsServices%) do (
  copy "%AppsRuntimeDir%\winsw\WinSW3.0.0.exe" "%AppsFilesDir%\tools\%%S.exe" /y
  copy "%AppsRuntimeDir%\winsw\%%S.xml" "%AppsFilesDir%\tools\%%S.xml" /y
)

REM ######## Copy nginx, SSL and Fluent Bit configs ########
copy "%AppsRuntimeDir%\nginx.conf" "%AppsNginxConfDir%\nginx.conf" /y
copy "%AppsDockerConfigDir%\nginx\proxy\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf" /y
copy "%AppsDockerConfigDir%\nginx\proxy\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf.tmpl" /y
copy "%AppsDockerConfigDir%\nginx\proxy\onlyoffice-proxy-ssl.conf" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl" /y
copy "%AppsDockerConfigDir%\nginx\proxy\letsencrypt.conf" "%AppsNginxConfDir%\includes\letsencrypt.conf" /y
copy "%AppsRuntimeDir%\sbin\apps-ssl-setup.ps1" "%AppsFilesDir%\sbin\apps-ssl-setup.ps1" /y
copy "%AppsDockerConfigDir%\fluent-bit.conf" "%AppsFilesDir%\config\fluent-bit.conf" /y
rmdir "%AppsOutDir%\publish" /s /q

REM ######## SSL configs ########
%sed% -i "s/this_host\|proxy_x_forwarded_host/host/g" "%AppsNginxConfDir%\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf.tmpl" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl"
%sed% -i "s/proxy_x_forwarded_port/server_port/g" "%AppsNginxConfDir%\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf.tmpl"
%sed% -i "s/proxy_x_forwarded_proto/scheme/g" "%AppsNginxConfDir%\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf.tmpl" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl"
%sed% -i "s/ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/#ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl"
%sed% -i "/quic\|alt-svc/Id" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl"
%sed% -i "s_\(.*root\).*;_\1 \"{APPDIR}letsencrypt\";_g" -i "%AppsNginxConfDir%\includes\letsencrypt.conf"
%sed% -i "s#/var/log/nginx/#logs/#g" "%AppsNginxConfDir%\onlyoffice-proxy.conf" "%AppsNginxConfDir%\onlyoffice-proxy.conf.tmpl" "%AppsNginxConfDir%\onlyoffice-proxy-ssl.conf.tmpl"
%sed% -i "s#/etc/nginx/html#conf/html#g" "%AppsNginxConfDir%\onlyoffice.conf"
%sed% -i "s/\/etc\/nginx\/\.htpasswd_dashboards/\.htpasswd_dashboards/g" "%AppsNginxConfDir%\onlyoffice.conf"

REM ######## Configure fluent-bit config for windows ########
rem PowerShell, not sed: the sed builds disagree on backslashes in a replacement, and the Windows tail input finds no files with / in the path
powershell -NoProfile -ExecutionPolicy Bypass -Command "$Conf = (Resolve-Path '%AppsFilesDir%\config\fluent-bit.conf').ProviderPath; $Text = [IO.File]::ReadAllText($Conf).Replace('/var/log/onlyoffice/', '{APPDIR}Logs\').Replace('**/', '**\'); [IO.File]::WriteAllText($Conf, $Text)" || exit /b 1
%sed% -i "/^\[OUTPUT\]/i\[INPUT]" "%AppsFilesDir%\config\fluent-bit.conf"
%sed% -i "/^\[OUTPUT\]/i\    Name                exec" "%AppsFilesDir%\config\fluent-bit.conf"
%sed% -i "/^\[OUTPUT\]/i\    Interval_Sec        86400" "%AppsFilesDir%\config\fluent-bit.conf"
%sed% -i "/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H 'Content-Type: application/json' -d '{\"query\": {\"range\": {\"@timestamp\": {\"lt\": \"now-30d\"}}}}'" "%AppsFilesDir%\config\fluent-bit.conf"
%sed% -i -e "s/\"/\\\\\"/g" -e "s/'/\"/g" "%AppsFilesDir%\config\fluent-bit.conf"
%sed% -i "s/^\[OUTPUT\]/\n[OUTPUT]/" "%AppsFilesDir%\config\fluent-bit.conf"

REM ######## Delete test and dev configs ########
del /f /q "%AppsFilesDir%\config\*.test.json"
del /f /q "%AppsFilesDir%\config\*.dev.json"

REM ######## Remove source maps, type declarations and debug symbols not needed at runtime ########
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $files = @(Get-ChildItem -LiteralPath '%AppsFilesDir%' -Recurse -File | Where-Object { $_.Name -match '\.(js|mjs|cjs|css|ts|mts|cts)\.map$' -or $_.Extension -eq '.pdb' -or ($_.Name -match '\.d\.[cm]?ts$' -and $_.FullName -match '\\node_modules\\') }); $files | Remove-Item -Force; Write-Host ('Removed ' + $files.Count + ' source maps, type declarations and debug symbols')"

REM ######## Remove translation tool metadata (locales\.meta), the client build skips it too ########
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $dirs = @(Get-ChildItem -LiteralPath '%AppsFilesDir%' -Recurse -Directory -Force -Filter '.meta' | Where-Object { $_.Parent.Name -eq 'locales' }); $dirs | Remove-Item -Recurse -Force; Write-Host ('Removed ' + $dirs.Count + ' locales\.meta folders')"

REM ######## Keep one copy of the node_modules packages the Next.js apps share ########
powershell -NoProfile -ExecutionPolicy Bypass -File "%AppsBuildDir%lib\dedupe-node-modules.ps1" -FilesDir "%AppsFilesDir%" || exit /b 1

REM ######## Product configs ########
rem add product version to config
%sed% "s/\"number\": *\"[0-9.]*\"/\"number\": \"%BUILD_VERSION%.%BUILD_NUMBER%\"/" -i "%AppsFilesDir%\config\appsettings.json"

rem default logging to warning
%sed% "s_\(\"Default\":\).*,_\1 \"Warning\",_g" -i "%AppsFilesDir%\config\appsettings.json"
%sed% "s_\(\"logLevel\":\).*_\1 \"warning\"_g" -i "%AppsFilesDir%\config\appsettings.services.json"
%sed% "/\"debug-info\": {/,/}/ s/\(\"enabled\": \)\".*\"/\1\"false\"/" -i "%AppsFilesDir%\config\appsettings.json"

%sed% "s_\(\"samesite\":\).*,_\1 \"None\",_g" -i "%AppsFilesDir%\config\appsettings.json"
%sed% "s_\(\"disableValidateToken\":\).*,_\1 \"false\",_g" -i "%AppsFilesDir%\config\appsettings.json"
%sed% "s_\(\"showPII\":\).*_\1 \"false\"_g" -i "%AppsFilesDir%\config\appsettings.json"

rem redirectUrl value replacement
%sed% "/weixinRedirectUrl/!s/teamlab.info/onlyoffice.com/g" -i "%AppsFilesDir%\config\autofac.consumers.json"
%sed% "s_\(\"wrongPortalNameUrl\":\).*,_\1 \"\",_g" -i "%AppsFilesDir%\public\scripts\config.json"

rem fix Bug 77834
%sed% "/ZiggyCreatures/! s/minlevel=[^ >]*/minlevel=\"Warn\"/g" -i "%AppsFilesDir%\config\nlog.config"

rem Remove AWSTarget from nlog.config
%sed% -i "/<target type=\"AWSTarget\" name=\"aws\"/,/<\/target>/d; /<target type=\"AWSTarget\" name=\"aws_sql\"/,/<\/target>/d" "%AppsFilesDir%\config\nlog.config"

rem delete nginx configs
del /f /q "%AppsNginxConfDir%\onlyoffice-login.conf"
del /f /q "%AppsNginxConfDir%\onlyoffice-story.conf"
del /f /q "%AppsNginxConfDir%\onlyoffice-management.conf"

rem Remove unused services from HealthCheck | Bug 64516
%sed% -i "/\"Name\": \"ASC.ApiCache\"/,/{/d" "%AppsFilesDir%\services\ASC.Web.HealthChecks.UI\service\appsettings.json"
%sed% -i "/\"Name\": \"ASC.ApiSystem\"/,/{/d" "%AppsFilesDir%\services\ASC.Web.HealthChecks.UI\service\appsettings.json"

rem configure nuget.config
copy "server\NuGet.config" . /y
%sed% -i "s/\.nuget\\packages/server\\.nuget\\packages/g" NuGet.config

REM ######## Build Utils ########
%nuget% install "%cd%\%AppsUtilsDir%\packages.config" -OutputDirectory "%cd%\%AppsUtilsDir%\packages"
%msbuild% "%AppsUtilsDir%\Utils.csproj"
copy "%AppsUtilsDir%\bin\Debug\Utils.CA.dll" "%AppsOutDir%\Utils.CA.dll" /y
rmdir "%AppsUtilsDir%\bin" /s /q
rmdir "%AppsUtilsDir%\obj" /s /q

REM ######## Delete temp files ########
del /f /q "%AppsInstallerDir%\*.back.*"
del /f /q sed*

REM ######## Build MySQL Server Installer ########
iscc /Qp /O"%cd%\%AppsOutDir%" /S"byparam="signtool" sign /a /n "%publisher%" /t http://timestamp.digicert.com $f" "%AppsInstallerDir%\MySQL Server Installer Runner.iss"

REM ######## Build OpenResty, OpenSearch and OpenSearchStack, or reuse them when their inputs did not change ########
call :build_aux_installer OpenResty "OpenResty-%openresty_version%.msi" "OpenResty" "%openresty_version%"
call :build_aux_installer OpenSearch "OpenSearch-%opensearch_version%.exe" "OpenSearch" ""
call :build_aux_installer OpenSearchStack "OpenSearchStack.msi" "OpenSearchStack" ""

REM ######## Build Apps package ########
%AdvancedInstaller% /edit "%AppsInstallerDir%\Apps.aip" /SetVersion %BUILD_VERSION%.%BUILD_NUMBER%
%AdvancedInstaller% /edit "%AppsInstallerDir%\Apps.Prerequisites.aip" /SetVersion %BUILD_VERSION%.%BUILD_NUMBER%

IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit "%AppsInstallerDir%\Apps.aip" /SetSig
%AdvancedInstaller% /edit "%AppsInstallerDir%\Apps.Prerequisites.aip" /SetSig
)

rem Build Apps Community
%AdvancedInstaller% /rebuild "%AppsInstallerDir%\Apps.aip" -buildslist APPS_COMMUNITY

rem Build Apps Enterprise
copy "%AppsInstallerDir%\Resources\License_Enterprise.rtf" "%AppsInstallerDir%\Resources\License.rtf" /y
copy "%AppsInstallerDir%\Resources\License_Enterprise_Redist.rtf" "%AppsInstallerDir%\Resources\License_Redist.rtf" /y

%AdvancedInstaller% /rebuild "%AppsInstallerDir%\Apps.aip" -buildslist APPS_ENTERPRISE

rem Build Apps Developer
copy "%AppsInstallerDir%\Resources\License_Developer.rtf" "%AppsInstallerDir%\Resources\License.rtf" /y
copy "%AppsInstallerDir%\Resources\License_Developer_Redist.rtf" "%AppsInstallerDir%\Resources\License_Redist.rtf" /y

%AdvancedInstaller% /rebuild "%AppsInstallerDir%\Apps.aip" -buildslist APPS_DEVELOPER

rem Build Apps Prerequisites
%AdvancedInstaller% /rebuild "%AppsInstallerDir%\Apps.Prerequisites.aip" -buildslist DefaultBuild

rem Keep the exit code of the last build for the Jenkins step
goto :eof

rem Build an auxiliary installer (%1 project, %2 package in out\publish, %3 comma-separated inputs in out, %4 version or empty) unless the cache has it
:build_aux_installer
set "AuxVersion="
if not "%~4"=="" set "AuxVersion=-Version "%~4""
set "AuxCache=powershell -NoProfile -ExecutionPolicy Bypass -File "%AppsBuildDir%lib\aux-installers-cache.ps1" -Project "%~1" -Package "%~2" -Inputs "%~3" %AuxVersion%"
%AuxCache% -Action Restore
if not errorlevel 1 goto :eof
if not "%~4"=="" %AdvancedInstaller% /edit "%AppsInstallerDir%\%~1.aip" /SetVersion %~4
IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit "%AppsInstallerDir%\%~1.aip" /SetSig
)
%AdvancedInstaller% /rebuild "%AppsInstallerDir%\%~1.aip"
if errorlevel 1 goto :eof
%AuxCache% -Action Save
goto :eof
