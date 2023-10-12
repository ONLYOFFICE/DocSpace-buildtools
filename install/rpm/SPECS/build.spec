%build

cd %{_builddir}/buildtools

bash install/common/systemd/build.sh

bash install/common/build-frontend.sh --srcpath %{_builddir}/client
bash install/common/build-backend.sh --srcpath %{_builddir}/server
bash install/common/publish-backend.sh --srcpath %{_builddir}/server

rename -f -v "s/product([^\/]*)$/%{product}\$1/g" install/common/*
sed -i "s/{{product}}/%{product}/g" install/common/logrotate/product-common

rm -f config/nginx/onlyoffice-login.conf
find config/ -type f -regex '.*\.\(test\|dev\).*' -delete

if ! grep -q 'var/www/%{product}' config/nginx/*.conf; then find config/nginx/ -name "*.conf" -exec sed -i "s@\(var/www/\)@\1%{product}/@" {} +; fi

json -I -f config/appsettings.services.json -e "this.logPath=\"/var/log/onlyoffice/%{product}\"" -e "this.socket={ 'path': '../ASC.Socket.IO/' }" \
-e "this.ssoauth={ 'path': '../ASC.SsoAuth/' }" -e "this.logLevel=\"warning\""  -e "this.core={ 'products': { 'folder': '%{buildpath}/products', 'subfolder': 'server'} }"
json -I -f config/appsettings.json -e "this.core.notify.postman=\"services\"" -e "this['debug-info'].enabled=\"false\"" -e "this.web.samesite=\"None\""
json -I -f config/apisystem.json -e "this.core.notify.postman=\"services\""
json -I -f %{_builddir}/publish/web/public/scripts/config.json -e "this.wrongPortalNameUrl=\"\""

sed 's_\(minlevel=\)"[^"]*"_\1"Warn"_g' -i config/nlog.config
sed 's/teamlab.info/onlyoffice.com/g' -i config/autofac.consumers.json

sed 's_etc/nginx_etc/openresty_g' -i config/nginx/*.conf
sed -e 's/$router_host/127.0.0.1/g' -e 's/the_host/host/g' -e 's/the_scheme/scheme/g' -e 's_includes_/etc/openresty/includes_g' -i install/docker/config/nginx/onlyoffice-proxy*.conf
sed -e '/.pid/d' -e '/temp_path/d' -e 's_etc/nginx_etc/openresty_g' -e 's/\.log/-openresty.log/g' -i install/docker/config/nginx/templates/nginx.conf.template
sed -i "s_\(.*root\).*;_\1 \"/var/www/%{product}\";_g" -i install/docker/config/nginx/letsencrypt.conf

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(dll\|dylib\|so\)$' -exec chmod 755 {} \;

find %{_builddir}/server/publish/ \
     %{_builddir}/server/ASC.Migration.Runner \
     -depth -type f -regex '.*\(so\)$' -exec strip {} \;
