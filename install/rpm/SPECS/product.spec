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

Source0:        https://github.com/ONLYOFFICE/%{product}-buildtools/archive/%{BRANCH_BUILDTOOLS}.tar.gz#/%{product_name}-buildtools-%{BRANCH_BUILDTOOLS}.tar.gz
Source1:        https://github.com/ONLYOFFICE/%{product}-client/archive/%{BRANCH_CLIENT}.tar.gz#/%{product_name}-client-%{BRANCH_CLIENT}.tar.gz
Source2:        https://github.com/ONLYOFFICE/%{product}-server/archive/%{BRANCH_SERVER}.tar.gz#/%{product_name}-server-%{BRANCH_SERVER}.tar.gz
Source3:        https://github.com/ONLYOFFICE/document-templates/archive/main/community-server.tar.gz#/document-templates-main-community-server.tar.gz
Source4:        https://github.com/ONLYOFFICE/dictionaries/archive/master.tar.gz#/dictionaries-master.tar.gz
Source5:        %{product}.rpmlintrc

BuildRequires:  nodejs >= 18.0
BuildRequires:  yarn
BuildRequires:  dotnet-sdk-7.0

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
Requires:       %name-radicale = %version-%release
Requires:       %name-socket = %version-%release
Requires:       %name-ssoauth = %version-%release
Requires:       %name-studio = %version-%release
Requires:       %name-studio-notify = %version-%release

%description
ONLYOFFICE DocSpace is a new way to collaborate on documents with teams, 
clients, partners, etc., based on the concept of rooms - special spaces with 
predefined permissions. 

%include package.spec

%prep
rm -rf %{_rpmdir}/%{_arch}/%{name}-* %{_builddir}/*

echo "%{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} %{SOURCE4}" | xargs -n 1 -P 5 tar -xzf
cp %{SOURCE5} .

mv -f %{product_name}-buildtools-%{BRANCH_BUILDTOOLS} buildtools
mv -f %{product_name}-client-%{BRANCH_CLIENT} client
mv -f %{product_name}-server-%{BRANCH_SERVER} server
mv -f %{_builddir}/dictionaries-master/*  %{_builddir}/client/common/Tests/Frontend.Translations.Tests/dictionaries/

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

%post 

%preun

%postun

%clean

rm -rf %{_builddir} %{buildroot} 

%changelog
*Mon Jan 16 2023 %{packager} - %{version}-%{release}
- Initial build.

%triggerin radicale -- python3, python36

if ! which python3; then
   if rpm -q python36; then
      update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1
   fi
fi

python3 -m pip install --upgrade radicale
python3 -m pip install --upgrade %{buildpath}/Tools/radicale/plugins/app_auth_plugin/.
python3 -m pip install --upgrade %{buildpath}/Tools/radicale/plugins/app_store_plugin/.
python3 -m pip install --upgrade %{buildpath}/Tools/radicale/plugins/app_rights_plugin/.
