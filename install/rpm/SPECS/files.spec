%files
%attr(744, root, root) %{_bindir}/%{product}-configuration

%files api
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/studio/ASC.Web.Api/
/usr/lib/systemd/system/%{product}-api.service
%dir %{buildpath}/studio/

%files api-system
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.ApiSystem/
/usr/lib/systemd/system/%{product}-api-system.service
%dir %{buildpath}/services/

%files backup
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Data.Backup/
/usr/lib/systemd/system/%{product}-backup.service
%dir %{buildpath}/services/

%files common
%defattr(-, onlyoffice, onlyoffice, -)
%config %attr(640, onlyoffice, onlyoffice) %{_sysconfdir}/onlyoffice/%{product}/*
%exclude %{_sysconfdir}/onlyoffice/%{product}/openresty
%attr(740, onlyoffice, onlyoffice) %{_sysconfdir}/onlyoffice/%{product}/document-formats/
%{_docdir}/%{name}-%{version}-%{release}/
%{_var}/log/onlyoffice/%{product}/
%dir %{_sysconfdir}/onlyoffice/
%dir %{_sysconfdir}/onlyoffice/%{product}/
%dir %{_sysconfdir}/onlyoffice/%{product}/.private/
%dir %{_var}/log/onlyoffice/

%files files-services
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Files/service/
/usr/lib/systemd/system/%{product}-files-services.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files notify
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Notify/
/usr/lib/systemd/system/%{product}-notify.service
%dir %{buildpath}/services/

%files files
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Files/server/
/usr/lib/systemd/system/%{product}-files.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files proxy
%defattr(-, onlyoffice, onlyoffice, -)
%config %{_sysconfdir}/openresty/includes/*
%config %{_sysconfdir}/openresty/conf.d/*
%config %{_sysconfdir}/openresty/html/*
%attr(744, root, root) %{_bindir}/%{product}-ssl-setup
%config %{_sysconfdir}/onlyoffice/%{product}/openresty/nginx.conf.template
%dir %{_sysconfdir}/onlyoffice/
%dir %{_sysconfdir}/onlyoffice/%{product}/
%dir %{_sysconfdir}/onlyoffice/%{product}/openresty/
%{buildpath}/public/
%{buildpath}/client/

%files studio-notify
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Studio.Notify/
/usr/lib/systemd/system/%{product}-studio-notify.service
%dir %{buildpath}/services/

%files people-server
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.People/server/
/usr/lib/systemd/system/%{product}-people-server.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/

%files socket
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Socket.IO/
/usr/lib/systemd/system/%{product}-socket.service
%dir %{buildpath}/services/

%files studio
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/studio/ASC.Web.Studio/
/usr/lib/systemd/system/%{product}-studio.service
%dir %{buildpath}/studio/

%files ssoauth
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.SsoAuth/
/usr/lib/systemd/system/%{product}-ssoauth.service
%dir %{buildpath}/services/

%files identity-api
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Identity.Registration
/usr/lib/systemd/system/%{product}-identity-api.service
%dir %{buildpath}/services/

%files identity-authorization
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Identity.Authorization
/usr/lib/systemd/system/%{product}-identity-authorization.service
%dir %{buildpath}/services/

%files clear-events
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.ClearEvents/
/usr/lib/systemd/system/%{product}-clear-events.service
%dir %{buildpath}/services/

%files backup-background
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Data.Backup.BackgroundTasks/
/usr/lib/systemd/system/%{product}-backup-background.service
%dir %{buildpath}/services/

%files doceditor
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Files/editor/
/usr/lib/systemd/system/%{product}-doceditor.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files migration-runner
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Migration.Runner/
/usr/lib/systemd/system/%{product}-migration-runner.service
%dir %{buildpath}/services/

%files login
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Login/login
/usr/lib/systemd/system/%{product}-login.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Login/

%files healthchecks
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.Web.HealthChecks.UI
/usr/lib/systemd/system/%{product}-healthchecks.service
%dir %{buildpath}/services/

%files plugins
%defattr(-, onlyoffice, onlyoffice, -)
%{_var}/www/onlyoffice/Data/Studio/webplugins/
%dir %{_var}/www/onlyoffice/Data/
%dir %{_var}/www/onlyoffice/Data/Studio/

%files sdk
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Sdk/sdk/
/usr/lib/systemd/system/%{product}-sdk.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Sdk/

%files management
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.Management/management/
/usr/lib/systemd/system/%{product}-management.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Management/

%files telegram
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/services/ASC.TelegramService/
/usr/lib/systemd/system/%{product}-telegram.service
%dir %{buildpath}/services/

%files ai
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.AI/server/
/usr/lib/systemd/system/%{product}-ai.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/

%files ai-service
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.AI/service/
/usr/lib/systemd/system/%{product}-ai-service.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/

%files mcp
%defattr(-, onlyoffice, onlyoffice, -)
%{buildpath}/products/ASC.AI/mcp/
/usr/lib/systemd/system/%{product}-mcp.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/
