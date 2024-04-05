%define         _binaries_in_noarch_packages_terminate_build   0
%define         _build_id_links none
%define         __os_install_post /usr/lib/rpm/brp-compress %{nil}

%global         product %{?another_product:%{another_product}}%{!?another_product:docspace}
%global         product_name %{?another_product_name:%{another_product_name}}%{!?another_product_name:DocSpace}
%global         product_sysname %{?another_product_sysname:%{another_product_sysname}}%{!?another_product_sysname:onlyoffice}
%global         url %{?another_url:%{another_url}}%{!?another_url:http://onlyoffice.com}
%global         vendor %{?another_vendor:%{another_vendor}}%{!?another_vendor:Ascensio System SIA}
%global         buildpath %{_var}/www/%{product}

Name:           %{product}
Summary:        Business productivity tools
Group:          Applications/Internet
Version:        %{version}
Release:        %{release}

AutoReqProv:    no

BuildArch:      noarch
URL:            %{url}
Vendor:         %{vendor}
Packager:       %{packager}
License:        AGPLv3

Source0:        https://github.com/%{toupper:product_sysname}/%{product}-buildtools/archive/master.tar.gz#/buildtools.tar.gz
Source1:        https://github.com/%{toupper:product_sysname}/%{product}-client/archive/master.tar.gz#/client.tar.gz
Source2:        https://github.com/%{toupper:product_sysname}/%{product}-server/archive/master.tar.gz#/server.tar.gz
Source3:        https://github.com/%{toupper:product_sysname}/document-templates/archive/main/community-server.tar.gz#/DocStore.tar.gz
Source4:        https://github.com/%{toupper:product_sysname}/dictionaries/archive/master.tar.gz#/dictionaries.tar.gz
Source5:        %{product}.rpmlintrc

BuildRequires:  nodejs >= 18.0
BuildRequires:  yarn
BuildRequires:  dotnet-sdk-8.0

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
%{toupper:product_sysname} %{product_name} is a new way to collaborate on documents with teams, 
clients, partners, etc., based on the concept of rooms - special spaces with 
predefined permissions. 

%include package.spec

%prep
rm -rf %{_rpmdir}/%{_arch}/%{name}-* %{_builddir}/*

tar -xf %{SOURCE0} --transform='s,^[^/]\+,buildtools,'   -C %{_builddir} 
tar -xf %{SOURCE1} --transform='s,^[^/]\+,client,'       -C %{_builddir} 
tar -xf %{SOURCE2} --transform='s,^[^/]\+,server,'       -C %{_builddir} 
tar -xf %{SOURCE4} --transform='s,^[^/]\+,dictionaries,' -C %{_builddir}/client/common/Tests/Frontend.Translations.Tests 
tar -xf %{SOURCE3} --transform='s,^[^/]\+,DocStore,'     -C %{_builddir}/server/products/ASC.Files/Server 
cp %{SOURCE5} .

%include build.spec

%include install.spec

%include files.spec

%pre

%pre common

getent group %{product_sysname} >/dev/null || groupadd -r %{product_sysname}
getent passwd %{product_sysname} >/dev/null || useradd -r -g %{product_sysname} -s /sbin/nologin %{product_sysname}

%pre proxy

# (DS v1.1.3) Removing old nginx configs to prevent conflicts before upgrading on OpenResty.
if [ -f /etc/nginx/conf.d/%{product_sysname}.conf ]; then
    rm -rf /etc/nginx/conf.d/%{product_sysname}*
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
