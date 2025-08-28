%package        backup
Summary:        Backup
Requires:       %name-common  = %version-%release 
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    backup
The service which handles API requests related to backup

%package        common
Summary:        Common
BuildArch:      noarch
%description    common
A package containing configure and scripts

%package        files-services
Summary:        Files-services
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
Requires:       ffmpeg-free
AutoReqProv:    no
BuildArch:      noarch
%description    files-services
The service which launches additional services related to file management:
 - ElasticSearchIndexService - indexes documents using Elasticsearch;
 - FeedAggregatorService - aggregates notifications;
 - FeedCleanerService - removes notifications;
 - FileConverterService - converts documents;
 - ThumbnailBuilderService - generates thumbnails for documents;
 - Launcher - removes outdated files from Trash;

%package        notify
Summary:        Notify
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    notify
The service which launches additional services
related to notifications about DocSpace events:
NotifySenderService which sends messages from the base,
and NotifyCleanerService which removes messages

%package        files
Summary:        Files
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    files
The service which handles API requests related to
documents and launches the OFormService service

%package        proxy
Summary:        Proxy
Requires:       %name-common  = %version-%release
Requires:       openresty
Requires:       mysql-community-client >= 5.7.0
AutoReqProv:    no
BuildArch:      noarch
%description    proxy
The service which is used as a web server and reverse proxy, 
it receives and handles requests, transmits them to other services, 
receives a response from them and returns it to the client

%package        studio-notify
Summary:        Studio-notify
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    studio-notify
The service responsible for creating notifications and
sending them to other services, for example, TelegramService and NotifyService

%package        people-server
Summary:        People-server
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    people-server
The service which handles API requests related to the People module

%package        socket
Summary:        Socket
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    socket
The service which provides two-way communication between a client and a server

%package        studio
Summary:        Studio
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    studio
The service which processes storage handlers and authorization pages

%package        api
Summary:        Api
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    api
The service which is used for working with a certain portal. This service
handles API requests not related to backup, documents, and the People
module, for example, requests related to settings, audit, authentication, etc.

%package        api-system
Summary:        Api-system
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    api-system
The service which is used for working with portals (creating, removing, etc.)

%package        ssoauth
Summary:        Ssoauth
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    ssoauth
The service responsible for enabling and configuring 
SAML-based single sign-on (SSO) authentication to provide a more quick, 
easy and secure way to access DocSpace for users

%package        identity-authorization
Summary:        Identity-Authorization
Requires:       %name-common  = %version-%release
Requires:       java-21-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-authorization
Identity-Authorization

%package        identity-api
Summary:        Identity-Api
Requires:       %name-common  = %version-%release
Requires:       java-21-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-api
Identity-Api

%package        clear-events
Summary:        Clear-events
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    clear-events
The service responsible for clearing the login_events and audit_events tables 
by LoginHistoryLifeTime and AuditTrailLifeTime to log out users after a timeout

%package        backup-background
Summary:        Backup-background
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    backup-background
The service which launches additional services related to backup creation:
 - BackupWorkerService - launches WorkerService which runs backup/restore, etc;
 - BackupListenerService - waits for a signal to delete backups;
 - BackupCleanerTempFileService - removes temporary backup files;
 - BackupCleanerService - removes outdated backup files;
 - BackupSchedulerService - runs backup according to a schedule;

%package        doceditor
Summary:        Doceditor
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    doceditor
The service which allows interaction with document-server

%package        migration-runner
Summary:        Migration-runner
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    migration-runner
The service responsible for the database creation.
A database connection is transferred to the service and
the service creates tables and populates them with values

%package        login
Summary:        Login
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    login
The service which is used for logging users and displaying the wizard

%package        healthchecks
Summary:        Healthchecks
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    healthchecks
The service which displays launched services

%package        plugins
Summary:        Plugins
Requires:       %name-common  = %version-%release
AutoReqProv:    no
BuildArch:      noarch
%description    plugins
This package includes plugins that extend DocSpace functionality

%package sdk
Summary:        Sdk
Requires:       %name-common = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description sdk
The service provides a Software Development Kit (SDK) with APIs and tools for custom
integrations and plugins

%package        management
Summary:        Management
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    management
The service responsible for DocSpace management interface

%package        telegram
Summary:        Telegram
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    telegram
Service responsible for Telegram integration
