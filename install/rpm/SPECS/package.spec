%package        backup
Packager:       %{packager}
Summary:        Backup
Group:          Applications/Internet
Requires:       %name-common  = %version-%release 
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    backup
The service which handles API requests related to backup

%package        common
Packager:       %{packager}
Summary:        Common
Group:          Applications/Internet
BuildArch:      noarch
%description    common
A package containing configure and scripts

%package        files-services
Packager:       %{packager}
Summary:        Files-services
Group:          Applications/Internet
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
Packager:       %{packager}
Summary:        Notify
Group:          Applications/Internet
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
Packager:       %{packager}
Summary:        Files
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    files
The service which handles API requests related to
documents and launches the OFormService service

%package        proxy
Packager:       %{packager}
Summary:        Proxy
Group:          Applications/Internet
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
Packager:       %{packager}
Summary:        Studio-notify
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    studio-notify
The service responsible for creating notifications and
sending them to other services, for example, TelegramService and NotifyService

%package        people-server
Packager:       %{packager}
Summary:        People-server
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    people-server
The service which handles API requests related to the People module

%package        socket
Packager:       %{packager}
Summary:        Socket
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    socket
The service which provides two-way communication between a client and a server

%package        studio
Packager:       %{packager}
Summary:        Studio
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    studio
The service which processes storage handlers and authorization pages

%package        api
Packager:       %{packager}
Summary:        Api
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    api
The service which is used for working with a certain portal. This service
handles API requests not related to backup, documents, and the People
module, for example, requests related to settings, audit, authentication, etc.

%package        api-system
Packager:       %{packager}
Summary:        Api-system
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    api-system
The service which is used for working with portals (creating, removing, etc.)

%package        ssoauth
Packager:       %{packager}
Summary:        Ssoauth
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    ssoauth
The service responsible for enabling and configuring 
SAML-based single sign-on (SSO) authentication to provide a more quick, 
easy and secure way to access DocSpace for users

%package        identity-authorization
Packager:       %{packager}
Summary:        Identity-Authorization
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       java-21-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-authorization
Identity-Authorization

%package        identity-api
Packager:       %{packager}
Summary:        Identity-Api
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       java-21-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-api
Identity-Api

%package        clear-events
Packager:       %{packager}
Summary:        Clear-events
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    clear-events
The service responsible for clearing the login_events and audit_events tables 
by LoginHistoryLifeTime and AuditTrailLifeTime to log out users after a timeout

%package        backup-background
Packager:       %{packager}
Summary:        Backup-background
Group:          Applications/Internet
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
Packager:       %{packager}
Summary:        Doceditor
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    doceditor
The service which allows interaction with document-server

%package        migration-runner
Packager:       %{packager}
Summary:        Migration-runner
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    migration-runner
The service responsible for the database creation.
A database connection is transferred to the service and
the service creates tables and populates them with values

%package        login
Packager:       %{packager}
Summary:        Login
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description    login
The service which is used for logging users and displaying the wizard

%package        healthchecks
Packager:       %{packager}
Summary:        Healthchecks
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
Requires:       dotnet-sdk-9.0
AutoReqProv:    no
BuildArch:      noarch
%description    healthchecks
The service which displays launched services

%package        plugins
Packager:       %{packager}
Summary:        Plugins
Group:          Applications/Internet
Requires:       %name-common  = %version-%release
AutoReqProv:    no
BuildArch:      noarch
%description    plugins
This package includes plugins that extend DocSpace functionality

%package sdk
Packager:       %{packager}
Summary:        Sdk
Group:          Applications/Internet
Requires:       %name-common = %version-%release
Requires:       nodejs >= 16.0
AutoReqProv:    no
BuildArch:      noarch
%description sdk
The service provides a Software Development Kit (SDK) with APIs and tools for custom
integrations and plugins

%package        langflow
Packager:       %{packager}
Summary:        Langflow
Group:          Applications/Internet
Requires:       %name-proxy = %version-%release
Requires:       %name-qdrant = %version-%release
Requires:       postgresql >= 12
Requires:       gcc
AutoReqProv:    no
BuildArch:      noarch
%description    langflow
Langflow is a tool for building and deploying AI agents and workflows.
It offers a visual authoring experience and an API server to integrate
agents into any application. It supports major LLMs, vector databases,
and AI tools.

%package        qdrant
Packager:       %{packager}
Summary:        Qdrant
Group:          Applications/Internet
AutoReqProv:    no
BuildArch:      noarch
%description    qdrant
Qdrant is a vector similarity search engine and vector database.
