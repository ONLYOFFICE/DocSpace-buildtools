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

Source0:        %{product}.rpmlintrc
Source1:        https://codeload.github.com/ONLYOFFICE/%{product}-buildtools/tar.gz/master#/buildtools.tar.gz
Source2:        https://codeload.github.com/ONLYOFFICE/%{product}-client/tar.gz/master#/client.tar.gz
Source3:        https://codeload.github.com/ONLYOFFICE/%{product}-server/tar.gz/master#/server.tar.gz
Source4:        https://codeload.github.com/ONLYOFFICE/document-templates/tar.gz/main/community-server#/DocStore.tar.gz
Source5:        https://codeload.github.com/ONLYOFFICE/ASC.Web.Campaigns/tar.gz/master#/campaigns.tar.gz
Source6:        https://codeload.github.com/ONLYOFFICE/%{product}-plugins/tar.gz/master#/plugins.tar.gz
Source7:        https://codeload.github.com/ONLYOFFICE/document-formats/tar.gz/master#/document-formats.tar.gz

BuildRequires:  nodejs >= 18.0
BuildRequires:  yarn
BuildRequires:  dotnet-sdk-9.0
BuildRequires:  unzip
BuildRequires:  java-21-openjdk-headless
BuildRequires:  maven

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
Requires:       %name-management = %version-%release
Requires:       %name-migration-runner = %version-%release
Requires:       %name-notify = %version-%release
Requires:       %name-people-server = %version-%release
Requires:       %name-proxy = %version-%release
Requires:       %name-plugins = %version-%release
Requires:       %name-socket = %version-%release
Requires:       %name-ssoauth = %version-%release
Requires:       %name-telegram = %version-%release
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

tar -xf %{SOURCE1} --transform='s,^[^/]\+,buildtools,'       -C %{_builddir} &
tar -xf %{SOURCE2} --transform='s,^[^/]\+,client,'           -C %{_builddir} &
tar -xf %{SOURCE3} --transform='s,^[^/]\+,server,'           -C %{_builddir} &
tar -xf %{SOURCE5} --transform='s,^[^/]\+,campaigns,'        -C %{_builddir} &
tar -xf %{SOURCE6} --transform='s,^[^/]\+,plugins,'          -C %{_builddir} &
wait
tar -xf %{SOURCE4} --transform='s,^[^/]\+,DocStore,'         -C %{_builddir}/server/products/ASC.Files/Server
tar -xf %{SOURCE7} --transform='s,^[^/]\+,document-formats,' -C %{_builddir}/buildtools/config
cp -rf %{SOURCE0} .

%include build.spec

%include install.spec

%include files.spec

%pre

%pre common

getent group onlyoffice >/dev/null || groupadd -r onlyoffice
getent passwd onlyoffice >/dev/null || useradd -r -g onlyoffice -s /usr/sbin/nologin -d %{_sysconfdir}/onlyoffice/%{product} onlyoffice

%pre identity-api

# (DS v3.1.0) fix encryption key generation issue
ENCRYPTION_PATH=%{_sysconfdir}/onlyoffice/%{product}/.private/encryption
if [ "$1" -eq 2 ] && [ ! -f "${ENCRYPTION_PATH}" ]; then
  echo 'secret' > "${ENCRYPTION_PATH}" && chmod 600 "${ENCRYPTION_PATH}"
fi

%post 

%preun

if [ "$1" -eq 0 ]; then
    systemctl list-unit-files | awk '/^%{product}.*\.service/{print $1}' \
    | xargs -r -I{} sh -c 'systemctl stop "{}" >/dev/null 2>&1 || true; systemctl disable "{}" >/dev/null 2>&1 || true'
    systemctl daemon-reload >/dev/null 2>&1 || true
fi

%postun

if [ "$1" -eq 0 ]; then
    systemctl reset-failed >/dev/null 2>&1 || true
    rm -rf %{buildpath}
fi

%changelog
*Mon Jan 16 2023 %{packager} - %{version}-%{release}
- Initial build.
