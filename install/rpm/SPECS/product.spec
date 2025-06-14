%define         _binaries_in_noarch_packages_terminate_build   0
%define         _build_id_links none
%define         __os_install_post /usr/lib/rpm/brp-compress %{nil}

%global         product docspace
%global         product_name DocSpace
%global         buildpath %{_var}/www/%{product}

Name:           %{product}
Summary:        Business productivity tools
Group:          Applications/Internet
Version:        %{version}
Release:        %{release}

AutoReqProv:    no

BuildArch:      noarch
URL:            http://onlyoffice.com
Vendor:         Ascensio System SIA
Packager:       %{packager}
License:        AGPLv3

Source0:        https://github.com/ONLYOFFICE/%{product}-buildtools/archive/master.tar.gz#/buildtools.tar.gz
Source1:        https://github.com/ONLYOFFICE/%{product}-client/archive/master.tar.gz#/client.tar.gz
Source2:        https://github.com/ONLYOFFICE/%{product}-server/archive/master.tar.gz#/server.tar.gz
Source3:        https://github.com/ONLYOFFICE/document-templates/archive/main/community-server.tar.gz#/DocStore.tar.gz
Source4:        https://github.com/ONLYOFFICE/ASC.Web.Campaigns/archive/master.tar.gz#/campaigns.tar.gz
Source5:        https://github.com/ONLYOFFICE/%{product}-plugins/archive/master.tar.gz#/plugins.tar.gz
Source6:        %{product}.rpmlintrc

BuildRequires:  nodejs >= 18.0
BuildRequires:  yarn
BuildRequires:  dotnet-sdk-9.0
BuildRequires:  unzip
BuildRequires:  java-21-openjdk-headless
BuildRequires:  maven

BuildRoot:      %_tmppath/%name-%version-%release.%arch

Requires:       %name-api = %version-%release
Requires:       %name-api-system = %version-%release
Requires:       %name-backup = %version-%release
Requires:       %name-backup-background = %version-%release
Requires:       %name-clear-events = %version-%release
Requires:       %name-doceditor = %version-%release
Requires:       %name-files = %version-%release
Requires:       %name-files-services = %version-%release
Requires:       %name-healthchecks = %version-%release
Requires:       %name-login = %version-%release
Requires:       %name-migration-runner = %version-%release
Requires:       %name-notify = %version-%release
Requires:       %name-people-server = %version-%release
Requires:       %name-proxy = %version-%release
Requires:       %name-plugins = %version-%release
Requires:       %name-socket = %version-%release
Requires:       %name-ssoauth = %version-%release
Requires:       %name-identity-authorization = %version-%release
Requires:       %name-identity-api = %version-%release
Requires:       %name-studio = %version-%release
Requires:       %name-studio-notify = %version-%release
Requires:       %name-sdk = %version-%release
Requires:       openssl

Conflicts:      %name-radicale

%description
ONLYOFFICE DocSpace is a new way to collaborate on documents with teams, 
clients, partners, etc., based on the concept of rooms - special spaces with 
predefined permissions. 

%include package.spec

%prep
rm -rf %{_rpmdir}/%{_arch}/%{name}-* %{_builddir}/*

tar -xf %{SOURCE0} --transform='s,^[^/]\+,buildtools,'   -C %{_builddir} &
tar -xf %{SOURCE1} --transform='s,^[^/]\+,client,'       -C %{_builddir} &
tar -xf %{SOURCE2} --transform='s,^[^/]\+,server,'       -C %{_builddir} &
tar -xf %{SOURCE4} --transform='s,^[^/]\+,campaigns,'    -C %{_builddir} &
tar -xf %{SOURCE5} --transform='s,^[^/]\+,plugins,'      -C %{_builddir} &
wait
tar -xf %{SOURCE3} --transform='s,^[^/]\+,DocStore,'     -C %{_builddir}/server/products/ASC.Files/Server
cp -rf %{SOURCE6} .

%include build.spec

%include install.spec

%include files.spec

%pre

%pre common

getent group onlyoffice >/dev/null || groupadd -r onlyoffice
getent passwd onlyoffice >/dev/null || useradd -r -g onlyoffice -s /sbin/nologin onlyoffice

%pre proxy

# (DS v1.1.3) Removing old nginx configs to prevent conflicts before upgrading on OpenResty.
if [ -f /etc/nginx/conf.d/onlyoffice.conf ]; then
    rm -rf /etc/nginx/conf.d/onlyoffice*
    systemctl reload nginx
fi

%pre identity-api

# (DS v3.1.0) fix encryption key generation issue
ENCRYPTION_PATH=%{_sysconfdir}/onlyoffice/%{product}/.private/encryption
if [ "$1" -eq 2 ] && [ ! -f "${ENCRYPTION_PATH}" ]; then
  echo 'secret' > "${ENCRYPTION_PATH}" && chmod 600 "${ENCRYPTION_PATH}"
fi

%post 

%preun

%postun

if [ "$1" -eq 0 ]; then
    rm -rf %{buildpath}
fi

%clean

rm -rf %{_builddir} %{buildroot} 

%include changelog.spec
