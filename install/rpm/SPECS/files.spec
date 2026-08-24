%files
%attr(744, root, root) %{_bindir}/%{product}-configuration

%files api
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/studio/ASC.Web.Api/
/usr/lib/systemd/system/%{product}-api.service
%dir %{buildpath}/studio/

%files api-system
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.ApiSystem/
/usr/lib/systemd/system/%{product}-api-system.service
%dir %{buildpath}/services/

%files backup
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Data.Backup/
/usr/lib/systemd/system/%{product}-backup.service
%dir %{buildpath}/services/

%files common
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%config %attr(640, %{package_sysname}, %{package_sysname}) %{_sysconfdir}/%{package_sysname}/%{product}/*.*
%dir %attr(750, %{package_sysname}, %{package_sysname}) %{_sysconfdir}/%{package_sysname}/%{product}/document-formats/
%config %attr(640, %{package_sysname}, %{package_sysname}) %{_sysconfdir}/%{package_sysname}/%{product}/document-formats/onlyoffice-docs-formats.json
%license %{_datadir}/licenses/%{name}/LICENSE
%license %{_datadir}/licenses/%{name}/LICENSE-CC-BY-SA
%{_var}/log/%{package_sysname}/%{product}/
%dir %{_sysconfdir}/%{package_sysname}/
%dir %{_sysconfdir}/%{package_sysname}/%{product}/
%dir %{_sysconfdir}/%{package_sysname}/%{product}/.private/
%dir %{_var}/log/%{package_sysname}/

%files files-worker
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Files/service/
/usr/lib/systemd/system/%{product}-files-worker.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files notify
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Notify/
/usr/lib/systemd/system/%{product}-notify.service
%dir %{buildpath}/services/

%files files
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Files/server/
/usr/lib/systemd/system/%{product}-files.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files proxy
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%config %{_sysconfdir}/openresty/includes/*
%config %{_sysconfdir}/openresty/conf.d/*
%config %{_sysconfdir}/openresty/html/*
%attr(744, root, root) %{_bindir}/%{product}-ssl-setup
%config %{_sysconfdir}/%{package_sysname}/%{product}/openresty/nginx.conf.template
%dir %{_sysconfdir}/%{package_sysname}/
%dir %{_sysconfdir}/%{package_sysname}/%{product}/
%dir %{_sysconfdir}/%{package_sysname}/%{product}/openresty/
%{buildpath}/public/
%{buildpath}/client/

%files studio-notify
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Studio.Notify/
/usr/lib/systemd/system/%{product}-studio-notify.service
%dir %{buildpath}/services/

%files people-server
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.People/server/
/usr/lib/systemd/system/%{product}-people-server.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/

%files socket
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Socket.IO/
/usr/lib/systemd/system/%{product}-socket.service
%dir %{buildpath}/services/

%files newai
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.NewAi/
/usr/lib/systemd/system/%{product}-newai.service
%dir %{buildpath}/services/

%files studio
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/studio/ASC.Web.Studio/
/usr/lib/systemd/system/%{product}-studio.service
%dir %{buildpath}/studio/

%files ssoauth
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.SsoAuth/
/usr/lib/systemd/system/%{product}-ssoauth.service
%dir %{buildpath}/services/

%files identity-api
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Identity.Registration
/usr/lib/systemd/system/%{product}-identity-api.service
%dir %{buildpath}/services/

%files identity-authorization
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Identity.Authorization
/usr/lib/systemd/system/%{product}-identity-authorization.service
%dir %{buildpath}/services/

%files clear-events
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.ClearEvents/
/usr/lib/systemd/system/%{product}-clear-events.service
%dir %{buildpath}/services/

%files backup-worker
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Data.Backup.Worker/
/usr/lib/systemd/system/%{product}-backup-worker.service
%dir %{buildpath}/services/

%files doceditor
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Files/editor/
/usr/lib/systemd/system/%{product}-doceditor.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files migration-runner
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Migration.Runner/
/usr/lib/systemd/system/%{product}-migration-runner.service
%dir %{buildpath}/services/

%files login
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Login/login
/usr/lib/systemd/system/%{product}-login.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Login/

%files healthchecks
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.Web.HealthChecks.UI
/usr/lib/systemd/system/%{product}-healthchecks.service
%dir %{buildpath}/services/

%files plugins
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{_var}/www/%{package_sysname}/Data/Studio/webplugins/
%dir %{_var}/www/%{package_sysname}/Data/
%dir %{_var}/www/%{package_sysname}/Data/Studio/

%files sdk
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Sdk/sdk/
/usr/lib/systemd/system/%{product}-sdk.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Sdk/

%files management
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.Management/management/
/usr/lib/systemd/system/%{product}-management.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Management/

%files telegram
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/services/ASC.TelegramService/
/usr/lib/systemd/system/%{product}-telegram.service
%dir %{buildpath}/services/

%files ai
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.AI/server/
/usr/lib/systemd/system/%{product}-ai.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/

%files ai-worker
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.AI/service/
/usr/lib/systemd/system/%{product}-ai-worker.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/

%files mcp
%defattr(-, %{package_sysname}, %{package_sysname}, -)
%{buildpath}/products/ASC.AI/mcp/
/usr/lib/systemd/system/%{product}-mcp.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.AI/
