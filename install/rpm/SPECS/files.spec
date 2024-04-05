%files
%attr(744, root, root) %{_bindir}/%{product}-configuration

%files api
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/studio/ASC.Web.Api/
/usr/lib/systemd/system/%{product}-api.service
%dir %{buildpath}/studio/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files api-system
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.ApiSystem/
/usr/lib/systemd/system/%{product}-api-system.service
%dir %{buildpath}/services/

%files backup
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Data.Backup/
/usr/lib/systemd/system/%{product}-backup.service
%dir %{buildpath}/services/
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files common
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%config %attr(640, %{product_sysname}, %{product_sysname}) %{_sysconfdir}/%{product_sysname}/%{product}/*
%exclude %{_sysconfdir}/%{product_sysname}/%{product}/openresty
%exclude %{_sysconfdir}/%{product_sysname}/%{product}/nginx
%{_docdir}/%{name}-%{version}-%{release}/
%config %{_sysconfdir}/logrotate.d/%{product}-common
%{_var}/log/%{product_sysname}/%{product}/
%dir %{_sysconfdir}/%{product_sysname}/
%dir %{_sysconfdir}/%{product_sysname}/%{product}/
%dir %{_sysconfdir}/%{product_sysname}/%{product}/.private/
%dir %{_var}/www/%{product_sysname}/Data
%dir %{_var}/log/%{product_sysname}/

%files files-services
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/products/ASC.Files/service/
/usr/lib/systemd/system/%{product}-files-services.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files notify
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Notify/
/usr/lib/systemd/system/%{product}-notify.service
%dir %{buildpath}/services/
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files files
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/products/ASC.Files/server/
/usr/lib/systemd/system/%{product}-files.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/

%files proxy
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%config %{_sysconfdir}/openresty/includes/*
%config %{_sysconfdir}/openresty/conf.d/*
%config %{_sysconfdir}/openresty/html/*
%attr(744, root, root) %{_bindir}/%{product}-ssl-setup
%config %{_sysconfdir}/%{product_sysname}/%{product}/openresty/nginx.conf.template
%dir %{_sysconfdir}/%{product_sysname}/
%dir %{_sysconfdir}/%{product_sysname}/%{product}/
%dir %{_sysconfdir}/%{product_sysname}/%{product}/openresty/
%{buildpath}/public/
%{buildpath}/client/

%files studio-notify
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Studio.Notify/
/usr/lib/systemd/system/%{product}-studio-notify.service
%dir %{buildpath}/services/
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files people-server
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/products/ASC.People/server/
/usr/lib/systemd/system/%{product}-people-server.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files socket
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Socket.IO/
/usr/lib/systemd/system/%{product}-socket.service
%dir %{buildpath}/services/
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.People/

%files studio
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/studio/ASC.Web.Studio/
/usr/lib/systemd/system/%{product}-studio.service
%dir %{buildpath}/studio/
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.People/
%dir %{buildpath}/products/ASC.People/server/
%dir %{buildpath}/products/ASC.Files/
%dir %{buildpath}/products/ASC.Files/server/

%files ssoauth
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.SsoAuth/
/usr/lib/systemd/system/%{product}-ssoauth.service
%dir %{buildpath}/services/

%files clear-events
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.ClearEvents/
/usr/lib/systemd/system/%{product}-clear-events.service
%dir %{buildpath}/services/

%files backup-background
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Data.Backup.BackgroundTasks/
/usr/lib/systemd/system/%{product}-backup-background.service
%dir %{buildpath}/services/

%files radicale
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/Tools/radicale/
%dir %{buildpath}/Tools/

%files doceditor
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/products/ASC.Files/editor/
/usr/lib/systemd/system/%{product}-doceditor.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Files/

%files migration-runner
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Migration.Runner/
/usr/lib/systemd/system/%{product}-migration-runner.service
%dir %{buildpath}/services/

%files login
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/products/ASC.Login/login
/usr/lib/systemd/system/%{product}-login.service
%dir %{buildpath}/products/
%dir %{buildpath}/products/ASC.Login/

%files healthchecks
%defattr(-, %{product_sysname}, %{product_sysname}, -)
%{buildpath}/services/ASC.Web.HealthChecks.UI
/usr/lib/systemd/system/%{product}-healthchecks.service
%dir %{buildpath}/services/
