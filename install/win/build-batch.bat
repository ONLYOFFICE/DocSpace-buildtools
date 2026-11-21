REM echo ######## Set variables ########
set "publisher="Ascensio System SIA""
set "nuget="%cd%\buildtools\install\win\nuget.exe""
set "opensearch_version=3.5.0"
set "openresty_version=1.27.1.1"

REM echo ######## Extracting and preparing files to build ########
%sevenzip% x buildtools\install\win\opensearch-%opensearch_version%.zip -o"buildtools\install\win" -y
%sevenzip% x buildtools\install\win\ingest-attachment-%opensearch_version%.zip -o"buildtools\install\win\OpenSearch\plugins\ingest-attachment" -y
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-security" "buildtools\install\win\OpenSearch\plugins\opensearch-security" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-job-scheduler" "buildtools\install\win\OpenSearch\plugins\opensearch-job-scheduler" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-index-management" "buildtools\install\win\OpenSearch\plugins\opensearch-index-management" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-knn" "buildtools\install\win\OpenSearch\plugins\opensearch-knn" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-neural-search" "buildtools\install\win\OpenSearch\plugins\opensearch-neural-search" /s /y /b /i
rmdir buildtools\install\win\opensearch-%opensearch_version%\plugins /s /q
xcopy "buildtools\install\win\opensearch-%opensearch_version%" "buildtools\install\win\OpenSearch" /s /y /b /i
rmdir buildtools\install\win\opensearch-%opensearch_version% /s /q
%sevenzip% x buildtools\install\win\openresty-%openresty_version%.zip -o"buildtools\install\win" -y
xcopy "buildtools\install\win\openresty-%openresty_version%-win64" "buildtools\install\win\OpenResty" /s /y /b /i
rmdir buildtools\install\win\openresty-%openresty_version%-win64 /s /q
md buildtools\install\win\OpenSearch\tools
md buildtools\install\win\OpenResty\tools
md buildtools\install\win\OpenResty\logs
md buildtools\install\win\OpenSearchStack\tools
md buildtools\install\win\Files\tools
md buildtools\install\win\Files\Logs
md buildtools\install\win\Files\Data
md buildtools\install\win\Files\sbin
md buildtools\install\win\Files\products\ASC.Files\server\temp
md buildtools\install\win\Files\products\ASC.People\server\temp
md buildtools\install\win\Files\services\ASC.Data.Backup\service\temp
md buildtools\install\win\Files\services\ASC.Notify\service\temp
md buildtools\install\win\Files\services\ASC.Files.Worker\service\temp
md buildtools\install\win\Files\services\ASC.Studio.Notify\service\temp
md buildtools\install\win\Files\services\ASC.Data.Backup.Worker\service\temp
md buildtools\install\win\Files\services\ASC.ClearEvents\service\temp
md buildtools\install\win\Files\services\ASC.ApiSystem\service\temp
md buildtools\install\win\Files\services\ASC.Web.Api\service\temp
md buildtools\install\win\Files\services\ASC.Web.Studio\service\temp
md buildtools\install\win\Files\services\ASC.Web.HealthChecks.UI\service\temp
xcopy "plugins\publish\*" "buildtools\install\win\Files\Data\Studio\webplugins" /s /e /y /i
xcopy "mcp\bin\*" "buildtools\install\win\Files\products\ASC.AI\mcp" /s /e /y /i
copy cloudhsm\signing-tool.ps1 "buildtools\install\win\signing-tool.ps1" /y
copy buildtools\install\win\WinSW.NET4.exe "buildtools\install\win\OpenResty\tools\OpenResty.exe" /y
copy buildtools\install\win\tools\OpenResty.xml "buildtools\install\win\OpenResty\tools\OpenResty.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Socket.IO.exe" /y
copy buildtools\install\win\tools\Socket.IO.xml "buildtools\install\win\Files\tools\Socket.IO.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\AI.Chat.exe" /y
copy buildtools\install\win\tools\AI.Chat.xml "buildtools\install\win\Files\tools\AI.Chat.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\SsoAuth.exe" /y
copy buildtools\install\win\tools\SsoAuth.xml "buildtools\install\win\Files\tools\SsoAuth.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\DocEditor.exe" /y
copy buildtools\install\win\tools\DocEditor.xml "buildtools\install\win\Files\tools\DocEditor.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Login.exe" /y
copy buildtools\install\win\tools\Login.xml "buildtools\install\win\Files\tools\Login.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Sdk.exe" /y
copy buildtools\install\win\tools\Sdk.xml "buildtools\install\win\Files\tools\Sdk.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\MCP.exe" /y
copy buildtools\install\win\tools\MCP.xml "buildtools\install\win\Files\tools\MCP.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Management.exe" /y
copy buildtools\install\win\tools\Management.xml "buildtools\install\win\Files\tools\Management.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\OpenSearch\tools\OpenSearch.exe" /y
copy buildtools\install\win\tools\OpenSearch.xml "buildtools\install\win\OpenSearch\tools\OpenSearch.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\OpenSearchStack\tools\OpenSearchDashboards.exe" /y
copy buildtools\install\win\tools\OpenSearchDashboards.xml "buildtools\install\win\OpenSearchStack\tools\OpenSearchDashboards.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Identity.Authorization.exe" /y
copy buildtools\install\win\tools\Identity.Authorization.xml "buildtools\install\win\Files\tools\Identity.Authorization.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Identity.Registration.exe" /y
copy buildtools\install\win\tools\Identity.Registration.xml "buildtools\install\win\Files\tools\Identity.Registration.xml" /y
copy "buildtools\install\win\nginx.conf" "buildtools\install\win\Files\nginx\conf\nginx.conf" /y
copy "buildtools\install\docker\config\nginx\proxy\onlyoffice-proxy.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf" /y
copy "buildtools\install\docker\config\nginx\proxy\onlyoffice-proxy.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl" /y
copy "buildtools\install\docker\config\nginx\proxy\onlyoffice-proxy-ssl.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl" /y
copy "buildtools\install\docker\config\nginx\proxy\letsencrypt.conf" "buildtools\install\win\Files\nginx\conf\includes\letsencrypt.conf" /y
copy "buildtools\install\win\sbin\apps-ssl-setup.ps1" "buildtools\install\win\Files\sbin\apps-ssl-setup.ps1" /y
copy "buildtools\install\docker\config\fluent-bit.conf" "buildtools\install\win\Files\config\fluent-bit.conf" /y
rmdir buildtools\install\win\publish /s /q

REM echo ######## SSL configs ########
%sed% -i "s/this_host\|proxy_x_forwarded_host/host/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s/proxy_x_forwarded_port/server_port/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl
%sed% -i "s/proxy_x_forwarded_proto/scheme/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s/ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/#ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "/quic\|alt-svc/Id" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s_\(.*root\).*;_\1 \"{APPDIR}letsencrypt\";_g" -i buildtools\install\win\Files\nginx\conf\includes\letsencrypt.conf
%sed% -i "s#/var/log/nginx/#logs/#g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s#/etc/nginx/html#conf/html#g" buildtools\install\win\Files\nginx\conf\onlyoffice.conf
%sed% -i "s/\/etc\/nginx\/\.htpasswd_dashboards/\.htpasswd_dashboards/g" buildtools\install\win\Files\nginx\conf\onlyoffice.conf

REM echo ######## Configure fluent-bit config for windows ########
rem PowerShell, not sed: the sed builds disagree on backslashes in a replacement, and the Windows tail input finds no files with / in the path
powershell -NoProfile -ExecutionPolicy Bypass -Command "$Conf = (Resolve-Path 'buildtools\install\win\Files\config\fluent-bit.conf').ProviderPath; $Text = [IO.File]::ReadAllText($Conf).Replace('/var/log/onlyoffice/', '{APPDIR}Logs\').Replace('**/', '**\'); [IO.File]::WriteAllText($Conf, $Text)" || exit /b 1
%sed% -i "/^\[OUTPUT\]/i\[INPUT]" buildtools\install\win\Files\config\fluent-bit.conf
%sed% -i "/^\[OUTPUT\]/i\    Name                exec" buildtools\install\win\Files\config\fluent-bit.conf
%sed% -i "/^\[OUTPUT\]/i\    Interval_Sec        86400" buildtools\install\win\Files\config\fluent-bit.conf
%sed% -i "/^\[OUTPUT\]/i\    Command             curl -s -X POST OPENSEARCH_SCHEME://OPENSEARCH_HOST:OPENSEARCH_PORT/OPENSEARCH_INDEX/_delete_by_query -H 'Content-Type: application/json' -d '{\"query\": {\"range\": {\"@timestamp\": {\"lt\": \"now-30d\"}}}}'" buildtools\install\win\Files\config\fluent-bit.conf
%sed% -i -e "s/\"/\\\\\"/g" -e "s/'/\"/g" buildtools\install\win\Files\config\fluent-bit.conf
%sed% -i "s/^\[OUTPUT\]/\n[OUTPUT]/" buildtools\install\win\Files\config\fluent-bit.conf

REM echo ######## Delete test and dev configs ########
del /f /q buildtools\install\win\Files\config\*.test.json
del /f /q buildtools\install\win\Files\config\*.dev.json

REM echo ######## Remove source maps, type declarations and debug symbols not needed at runtime ########
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $files = @(Get-ChildItem -LiteralPath 'buildtools\install\win\Files' -Recurse -File | Where-Object { $_.Name -match '\.(js|mjs|cjs|css|ts|mts|cts)\.map$' -or $_.Extension -eq '.pdb' -or ($_.Name -match '\.d\.[cm]?ts$' -and $_.FullName -match '\\node_modules\\') }); $files | Remove-Item -Force; Write-Host ('Removed ' + $files.Count + ' source maps, type declarations and debug symbols')"

REM echo ######## Remove translation tool metadata (locales\.meta), the client build skips it too ########
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference = 'Stop'; $dirs = @(Get-ChildItem -LiteralPath 'buildtools\install\win\Files' -Recurse -Directory -Force -Filter '.meta' | Where-Object { $_.Parent.Name -eq 'locales' }); $dirs | Remove-Item -Recurse -Force; Write-Host ('Removed ' + $dirs.Count + ' locales\.meta folders')"

REM echo ######## Keep one copy of the node_modules packages the Next.js apps share ########
powershell -NoProfile -ExecutionPolicy Bypass -File buildtools\install\win\dedupe-node-modules.ps1 -FilesDir buildtools\install\win\Files || exit /b 1

::add product version to config
%sed% "s/\"number\": *\"[0-9.]*\"/\"number\": \"%BUILD_VERSION%.%BUILD_NUMBER%\"/" -i buildtools\install\win\Files\config\appsettings.json

::default logging to warning
%sed% "s_\(\"Default\":\).*,_\1 \"Warning\",_g" -i buildtools\install\win\Files\config\appsettings.json
%sed% "s_\(\"logLevel\":\).*_\1 \"warning\"_g" -i buildtools\install\win\Files\config\appsettings.services.json
%sed% "/\"debug-info\": {/,/}/ s/\(\"enabled\": \)\".*\"/\1\"false\"/" -i buildtools\install\win\Files\config\appsettings.json

%sed% "s_\(\"samesite\":\).*,_\1 \"None\",_g" -i buildtools\install\win\Files\config\appsettings.json
%sed% "s_\(\"disableValidateToken\":\).*,_\1 \"false\",_g" -i buildtools\install\win\Files\config\appsettings.json
%sed% "s_\(\"showPII\":\).*_\1 \"false\"_g" -i buildtools\install\win\Files\config\appsettings.json

::redirectUrl value replacement
%sed% "/weixinRedirectUrl/!s/teamlab.info/onlyoffice.com/g" -i buildtools\install\win\Files\config\autofac.consumers.json
%sed% "s_\(\"wrongPortalNameUrl\":\).*,_\1 \"\",_g" -i buildtools\install\win\Files\public\scripts\config.json

::fix Bug 77834
%sed% "/ZiggyCreatures/! s/minlevel=[^ >]*/minlevel=\"Warn\"/g" -i buildtools\install\win\Files\config\nlog.config

REM echo ######## Remove AWSTarget from nlog.config ########
%sed% -i "/<target type=\"AWSTarget\" name=\"aws\"/,/<\/target>/d; /<target type=\"AWSTarget\" name=\"aws_sql\"/,/<\/target>/d" buildtools\install\win\Files\config\nlog.config

::delete nginx configs
del /f /q buildtools\install\win\Files\nginx\conf\onlyoffice-login.conf
del /f /q buildtools\install\win\Files\nginx\conf\onlyoffice-story.conf
del /f /q buildtools\install\win\Files\nginx\conf\onlyoffice-management.conf

::Remove unused services from HealthCheck | Bug 64516
%sed% -i "/\"Name\": \"ASC.ApiCache\"/,/{/d" buildtools\install\win\Files\services\ASC.Web.HealthChecks.UI\service\appsettings.json
%sed% -i "/\"Name\": \"ASC.ApiSystem\"/,/{/d" buildtools\install\win\Files\services\ASC.Web.HealthChecks.UI\service\appsettings.json

::configure nuget.config
copy "server\NuGet.config" . /y
%sed% -i "s/\.nuget\\packages/server\\.nuget\\packages/g" NuGet.config

REM echo ######## Build Utils ########
%nuget% install %cd%\buildtools\install\win\CustomActions\C#\Utils\packages.config -OutputDirectory %cd%\buildtools\install\win\CustomActions\C#\Utils\packages
%msbuild% buildtools\install\win\CustomActions\C#\Utils\Utils.csproj
copy buildtools\install\win\CustomActions\C#\Utils\bin\Debug\Utils.CA.dll buildtools\install\win\Utils.CA.dll /y
rmdir buildtools\install\win\CustomActions\C#\Utils\bin /s /q
rmdir buildtools\install\win\CustomActions\C#\Utils\obj /s /q

REM echo ######## Delete temp files ########
del /f /q buildtools\install\win\*.back.*
del /f /q sed*

REM echo ######## Build MySQL Server Installer ########
iscc /Qp /S"byparam="signtool" sign /a /n "%publisher%" /t http://timestamp.digicert.com $f" "buildtools\install\win\MySQL Server Installer Runner.iss"

REM echo ######## Build OpenResty, OpenSearch and OpenSearchStack, or reuse them when their inputs did not change ########
call :build_aux_installer OpenResty "OpenResty-%openresty_version%.msi" "OpenResty" "%openresty_version%"
call :build_aux_installer OpenSearch "OpenSearch-%opensearch_version%.exe" "OpenSearch" ""
call :build_aux_installer OpenSearchStack "OpenSearchStack.msi" "OpenSearchStack" ""

REM echo ######## Build Apps package ########
%AdvancedInstaller% /edit buildtools\install\win\Apps.aip /SetVersion %BUILD_VERSION%.%BUILD_NUMBER%
%AdvancedInstaller% /edit buildtools\install\win\Apps.Prerequisites.aip /SetVersion %BUILD_VERSION%.%BUILD_NUMBER%

IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\Apps.aip /SetSig
%AdvancedInstaller% /edit buildtools\install\win\Apps.Prerequisites.aip /SetSig
)

:: Build Apps Community
%AdvancedInstaller% /rebuild buildtools\install\win\Apps.aip -buildslist APPS_COMMUNITY

:: Build Apps Enterprise
copy "buildtools\install\win\Resources\License_Enterprise.rtf" "buildtools\install\win\Resources\License.rtf" /y
copy "buildtools\install\win\Resources\License_Enterprise_Redist.rtf" "buildtools\install\win\Resources\License_Redist.rtf" /y

%AdvancedInstaller% /rebuild buildtools\install\win\Apps.aip -buildslist APPS_ENTERPRISE

:: Build Apps Developer
copy "buildtools\install\win\Resources\License_Developer.rtf" "buildtools\install\win\Resources\License.rtf" /y
copy "buildtools\install\win\Resources\License_Developer_Redist.rtf" "buildtools\install\win\Resources\License_Redist.rtf" /y

%AdvancedInstaller% /rebuild buildtools\install\win\Apps.aip -buildslist APPS_DEVELOPER

:: Build Apps Prerequisites
%AdvancedInstaller% /rebuild buildtools\install\win\Apps.Prerequisites.aip -buildslist DefaultBuild

rem Keep the exit code of the last build for the Jenkins step
goto :eof

rem Build an auxiliary installer (%1 project, %2 package in publish, %3 comma-separated inputs, %4 version or empty) unless the cache has it
:build_aux_installer
set "AuxVersion="
if not "%~4"=="" set "AuxVersion=-Version "%~4""
set "AuxCache=powershell -NoProfile -ExecutionPolicy Bypass -File buildtools\install\win\aux-installers-cache.ps1 -Project "%~1" -Package "%~2" -Inputs "%~3" %AuxVersion%"
%AuxCache% -Action Restore
if not errorlevel 1 goto :eof
if not "%~4"=="" %AdvancedInstaller% /edit buildtools\install\win\%~1.aip /SetVersion %~4
IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\%~1.aip /SetSig
)
%AdvancedInstaller% /rebuild buildtools\install\win\%~1.aip
if errorlevel 1 goto :eof
%AuxCache% -Action Save
goto :eof
