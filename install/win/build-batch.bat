REM echo ######## Set variables ########
set "publisher="Ascensio System SIA""
set "nuget="%cd%\server\thirdparty\SimpleRestServices\src\.nuget\NuGet.exe""
set "environment=production"
set "opensearch_version=2.11.1"

REM echo ######## Extracting and preparing files to build ########
%sevenzip% x buildtools\install\win\opensearch-%opensearch_version%.zip -o"buildtools\install\win" -y
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-security" "buildtools\install\win\OpenSearch\plugins\opensearch-security" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-job-scheduler" "buildtools\install\win\OpenSearch\plugins\opensearch-job-scheduler" /s /y /b /i
xcopy "buildtools\install\win\opensearch-%opensearch_version%\plugins\opensearch-index-management" "buildtools\install\win\OpenSearch\plugins\opensearch-index-management" /s /y /b /i
rmdir buildtools\install\win\opensearch-%opensearch_version%\plugins /s /q
xcopy "buildtools\install\win\opensearch-%opensearch_version%" "buildtools\install\win\OpenSearch" /s /y /b /i
rmdir buildtools\install\win\opensearch-%opensearch_version% /s /q
md buildtools\install\win\OpenSearch\tools
md buildtools\install\win\OpenResty\tools
md buildtools\install\win\OpenSearchStack\tools
md buildtools\install\win\Files\tools
md buildtools\install\win\Files\Logs
md buildtools\install\win\Files\Data
md buildtools\install\win\Files\sbin
md buildtools\install\win\Files\products\ASC.Files\server\temp
md buildtools\install\win\Files\products\ASC.People\server\temp
md buildtools\install\win\Files\services\ASC.Data.Backup\service\temp
md buildtools\install\win\Files\services\ASC.Files.Service\service\temp
md buildtools\install\win\Files\services\ASC.Notify\service\temp
md buildtools\install\win\Files\services\ASC.Studio.Notify\service\temp
md buildtools\install\win\Files\services\ASC.Data.Backup.BackgroundTasks\service\temp
md buildtools\install\win\Files\services\ASC.ClearEvents\service\temp
md buildtools\install\win\Files\services\ASC.Web.Api\service\temp
md buildtools\install\win\Files\services\ASC.Web.Studio\service\temp
md buildtools\install\win\Files\services\ASC.Web.HealthChecks.UI\service\temp
copy buildtools\install\win\WinSW.NET4.exe "buildtools\install\win\OpenResty\tools\OpenResty.exe" /y
copy buildtools\install\win\tools\OpenResty.xml "buildtools\install\win\OpenResty\tools\OpenResty.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Socket.IO.exe" /y
copy buildtools\install\win\tools\Socket.IO.xml "buildtools\install\win\Files\tools\Socket.IO.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\SsoAuth.exe" /y
copy buildtools\install\win\tools\SsoAuth.xml "buildtools\install\win\Files\tools\SsoAuth.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\DocEditor.exe" /y
copy buildtools\install\win\tools\DocEditor.xml "buildtools\install\win\Files\tools\DocEditor.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\Files\tools\Login.exe" /y
copy buildtools\install\win\tools\Login.xml "buildtools\install\win\Files\tools\Login.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\OpenSearch\tools\OpenSearch.exe" /y
copy buildtools\install\win\tools\OpenSearch.xml "buildtools\install\win\OpenSearch\tools\OpenSearch.xml" /y
copy buildtools\install\win\WinSW3.0.0.exe "buildtools\install\win\OpenSearchStack\tools\OpenSearchDashboards.exe" /y
copy buildtools\install\win\tools\OpenSearchDashboards.xml "buildtools\install\win\OpenSearchStack\tools\OpenSearchDashboards.xml" /y
copy "buildtools\install\win\nginx.conf" "buildtools\install\win\Files\nginx\conf\nginx.conf" /y
copy "buildtools\install\docker\config\nginx\onlyoffice-proxy.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf" /y
copy "buildtools\install\docker\config\nginx\onlyoffice-proxy.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl" /y
copy "buildtools\install\docker\config\nginx\onlyoffice-proxy-ssl.conf" "buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl" /y
copy "buildtools\install\docker\config\nginx\letsencrypt.conf" "buildtools\install\win\Files\nginx\conf\includes\letsencrypt.conf" /y
copy "buildtools\install\win\sbin\docspace-ssl-setup.ps1" "buildtools\install\win\Files\sbin\docspace-ssl-setup.ps1" /y
rmdir buildtools\install\win\publish /s /q

REM echo ######## SSL configs ########
%sed% -i "s/this_host\|proxy_x_forwarded_host/host/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s/proxy_x_forwarded_port/server_port/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl
%sed% -i "s/proxy_x_forwarded_proto/scheme/g" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf buildtools\install\win\Files\nginx\conf\onlyoffice-proxy.conf.tmpl buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s/ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/#ssl_dhparam \/etc\/ssl\/certs\/dhparam.pem;/" buildtools\install\win\Files\nginx\conf\onlyoffice-proxy-ssl.conf.tmpl
%sed% -i "s_\(.*root\).*;_\1 \"{APPDIR}letsencrypt\";_g" -i buildtools\install\win\Files\nginx\conf\includes\letsencrypt.conf
%sed% -i "s#/etc/nginx/html#conf/html#g" buildtools\install\win\Files\nginx\conf\onlyoffice.conf

REM echo ######## Delete test and dev configs ########
del /f /q buildtools\install\win\Files\config\*.test.json
del /f /q buildtools\install\win\Files\config\*.dev.json

::default logging to warning
%sed% "s_\(\"Default\":\).*,_\1 \"Warning\",_g" -i buildtools\install\win\Files\config\appsettings.json
%sed% "s_\(\"logLevel\":\).*_\1 \"warning\"_g" -i buildtools\install\win\Files\config\appsettings.services.json
%sed% "/\"debug-info\": {/,/}/ s/\(\"enabled\": \)\".*\"/\1\"false\"/" -i buildtools\install\win\Files\config\appsettings.json

%sed% "s_\(\"samesite\":\).*,_\1 \"None\",_g" -i buildtools\install\win\Files\config\appsettings.json

::redirectUrl value replacement
%sed% "s/teamlab.info/onlyoffice.com/g" -i buildtools\install\win\Files\config\autofac.consumers.json
%sed% "s_\(\"wrongPortalNameUrl\":\).*,_\1 \"\",_g" -i buildtools\install\win\Files\public\scripts\config.json

REM echo ######## Remove AWSTarget from nlog.config ########
%sed% -i "/<target type=\"AWSTarget\" name=\"aws\"/,/<\/target>/d; /<target type=\"AWSTarget\" name=\"aws_sql\"/,/<\/target>/d" buildtools\install\win\Files\config\nlog.config

::edit environment
%sed% -i "s/\(\W\)PRODUCT.ENVIRONMENT.SUB\(\W\)/\1%environment%\2/g" buildtools\install\win\DocSpace.aip

::delete nginx configs
del /f /q buildtools\install\win\Files\nginx\conf\onlyoffice-login.conf
del /f /q buildtools\install\win\Files\nginx\conf\onlyoffice-story.conf

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

REM echo ######## Build OpenResty ########
IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\OpenResty.aip /SetSig
%AdvancedInstaller% /edit buildtools\install\win\OpenResty.aip /SetDigitalCertificateFile -file %onlyoffice_codesign_path% -password "%onlyoffice_codesign_password%"
)
%AdvancedInstaller% /rebuild buildtools\install\win\OpenResty.aip

REM echo ######## Build OpenSearch ########
IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\OpenSearch.aip /SetSig
%AdvancedInstaller% /edit buildtools\install\win\OpenSearch.aip /SetDigitalCertificateFile -file %onlyoffice_codesign_path% -password "%onlyoffice_codesign_password%"
)
%AdvancedInstaller% /rebuild buildtools\install\win\OpenSearch.aip

REM echo ######## Build OpenSearchStack ########
IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\OpenSearchStack.aip /SetSig
%AdvancedInstaller% /edit buildtools\install\win\OpenSearchStack.aip /SetDigitalCertificateFile -file %onlyoffice_codesign_path% -password "%onlyoffice_codesign_password%"
)
%AdvancedInstaller% /rebuild buildtools\install\win\OpenSearchStack.aip

REM echo ######## Build DocSpace package ########
%AdvancedInstaller% /edit buildtools\install\win\DocSpace.aip /SetVersion %BUILD_VERSION%.%BUILD_NUMBER%

IF "%SignBuild%"=="true" (
%AdvancedInstaller% /edit buildtools\install\win\DocSpace.aip /SetSig
%AdvancedInstaller% /edit buildtools\install\win\DocSpace.aip /SetDigitalCertificateFile -file %onlyoffice_codesign_path% -password "%onlyoffice_codesign_password%"
)

:: Build DocSpace Community
%AdvancedInstaller% /rebuild buildtools\install\win\DocSpace.aip -buildslist DOCSPACE_COMMUNITY

:: Build DocSpace Enterprise
copy "buildtools\install\win\Resources\License_Enterprise.rtf" "buildtools\install\win\Resources\License.rtf" /y
copy "buildtools\install\win\Resources\License_Enterprise_Redist.rtf" "buildtools\install\win\Resources\License_Redist.rtf" /y

%AdvancedInstaller% /rebuild buildtools\install\win\DocSpace.aip -buildslist DOCSPACE_ENTERPRISE
