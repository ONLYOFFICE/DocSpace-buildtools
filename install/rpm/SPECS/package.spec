%package        backup
Provides:       %{legacy_product}-backup = %{version}-%{release}
Obsoletes:      %{legacy_product}-backup < %{version}-%{release}
Summary:        Backup
Requires:       %name-common  = %version-%release 
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    backup
The service which handles API requests related to backup.

%package        common
Provides:       %{legacy_product}-common = %{version}-%{release}
Obsoletes:      %{legacy_product}-common < %{version}-%{release}
Summary:        Common
BuildArch:      noarch
%description    common
A package containing configs and scripts.

%package        files-worker
Provides:       %{legacy_product}-files-worker = %{version}-%{release}
Obsoletes:      %{legacy_product}-files-worker < %{version}-%{release}
Summary:        Files-worker
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
Requires:       /usr/bin/ffmpeg
AutoReqProv:    no
BuildArch:      noarch
%description    files-worker
The service which launches additional services related to file management:
 - ElasticSearchIndexService - indexes documents using Elasticsearch;
 - FeedAggregatorService - aggregates notifications;
 - FeedCleanerService - removes notifications;
 - FileConverterService - converts documents;
 - ThumbnailBuilderService - generates thumbnails for documents;
 - Launcher - removes outdated files from Trash;

%package        notify
Provides:       %{legacy_product}-notify = %{version}-%{release}
Obsoletes:      %{legacy_product}-notify < %{version}-%{release}
Summary:        Notify
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    notify
The service which launches additional services related to notifications
about %{product_name} events: NotifySenderService which sends messages from the
base, and NotifyCleanerService which removes messages.

%package        files
Provides:       %{legacy_product}-files = %{version}-%{release}
Obsoletes:      %{legacy_product}-files < %{version}-%{release}
Summary:        Files
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    files
The REST API server for working with documents. The service which handles
API requests related to documents and launches the OFormService service.

%package        proxy
Provides:       %{legacy_product}-proxy = %{version}-%{release}
Obsoletes:      %{legacy_product}-proxy < %{version}-%{release}
Summary:        Proxy
Requires:       %name-common  = %version-%release
Requires:       openresty
Requires:       mysql-community-client >= 5.7.0
AutoReqProv:    no
BuildArch:      noarch
%description    proxy
The service which is used as a web server and reverse proxy, 
it receives and handles requests, transmits them to other services, 
receives a response from them and returns it to the client.

%package        studio-notify
Provides:       %{legacy_product}-studio-notify = %{version}-%{release}
Obsoletes:      %{legacy_product}-studio-notify < %{version}-%{release}
Summary:        Studio-notify
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    studio-notify
The service responsible for creating notifications and
sending them to other services, for example, TelegramService and NotifyService.

%package        people-server
Provides:       %{legacy_product}-people-server = %{version}-%{release}
Obsoletes:      %{legacy_product}-people-server < %{version}-%{release}
Summary:        People-server
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    people-server
The service which handles API requests related to the People module.

%package        socket
Provides:       %{legacy_product}-socket = %{version}-%{release}
Obsoletes:      %{legacy_product}-socket < %{version}-%{release}
Summary:        Socket
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    socket
The service which provides two-way communication between a web browser
and the server.

%package        newai
Provides:       %{legacy_product}-newai = %{version}-%{release}
Obsoletes:      %{legacy_product}-newai < %{version}-%{release}
Summary:        NewAi
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    newai
The service which provides AI chat features and MCP tool integrations.

%package        studio
Provides:       %{legacy_product}-studio = %{version}-%{release}
Obsoletes:      %{legacy_product}-studio < %{version}-%{release}
Summary:        Studio
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    studio
The service which processes storage handlers.

%package        api
Provides:       %{legacy_product}-api = %{version}-%{release}
Obsoletes:      %{legacy_product}-api < %{version}-%{release}
Summary:        Api
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    api
The service which is used for working with a certain portal. This service
handles API requests not related to backup, documents, and the People
module, for example, requests related to settings, audit, authentication, etc.

%package        api-system
Provides:       %{legacy_product}-api-system = %{version}-%{release}
Obsoletes:      %{legacy_product}-api-system < %{version}-%{release}
Summary:        Api-system
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    api-system
The service which is used for working with portals (creating, removing
portals, etc.)

%package        ssoauth
Provides:       %{legacy_product}-ssoauth = %{version}-%{release}
Obsoletes:      %{legacy_product}-ssoauth < %{version}-%{release}
Summary:        Ssoauth
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    ssoauth
The service responsible for enabling and configuring 
SAML-based single sign-on (SSO) authentication to provide a more quick, 
easy and secure way to access %{product_name} for users.

%package        identity-authorization
Provides:       %{legacy_product}-identity-authorization = %{version}-%{release}
Obsoletes:      %{legacy_product}-identity-authorization < %{version}-%{release}
Summary:        Identity-Authorization
Requires:       %name-common  = %version-%release
Requires:       java-%{java_version}-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-authorization
The service responsible for authentication methods used to access
%{product_name}, e.g., the OAuth technology.

%package        identity-api
Provides:       %{legacy_product}-identity-api = %{version}-%{release}
Obsoletes:      %{legacy_product}-identity-api < %{version}-%{release}
Summary:        Identity-Api
Requires:       %name-common  = %version-%release
Requires:       java-%{java_version}-openjdk-headless
AutoReqProv:    no
BuildArch:      noarch
%description    identity-api
The service responsible for managing user identities and authentication
within %{product_name} by using the OAuth technology.

%package        clear-events
Provides:       %{legacy_product}-clear-events = %{version}-%{release}
Obsoletes:      %{legacy_product}-clear-events < %{version}-%{release}
Summary:        Clear-events
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    clear-events
The service responsible for clearing the login_events and audit_events
tables by LoginHistoryLifeTime and AuditTrailLifeTime to log out users
after a timeout.

%package        backup-worker
Provides:       %{legacy_product}-backup-worker = %{version}-%{release}
Obsoletes:      %{legacy_product}-backup-worker < %{version}-%{release}
Summary:        Backup-worker
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    backup-worker
The service which launches additional services related to backup creation:
 - BackupWorkerService - launches WorkerService which runs backup/restore, etc;
 - BackupListenerService - waits for a signal to delete backups;
 - BackupCleanerTempFileService - removes temporary backup files;
 - BackupCleanerService - removes outdated backup files;
 - BackupSchedulerService - runs backup according to a schedule;

%package        doceditor
Provides:       %{legacy_product}-doceditor = %{version}-%{release}
Obsoletes:      %{legacy_product}-doceditor < %{version}-%{release}
Summary:        Doceditor
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    doceditor
The service which allows interaction with document-server.

%package        migration-runner
Provides:       %{legacy_product}-migration-runner = %{version}-%{release}
Obsoletes:      %{legacy_product}-migration-runner < %{version}-%{release}
Summary:        Migration-runner
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    migration-runner
The service responsible for the database creation.
A database connection is transferred to the service and
the service creates tables and populates them with values.

%package        login
Provides:       %{legacy_product}-login = %{version}-%{release}
Obsoletes:      %{legacy_product}-login < %{version}-%{release}
Summary:        Login
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    login
The service which is used for logging users and displaying the wizard.

%package        healthchecks
Provides:       %{legacy_product}-healthchecks = %{version}-%{release}
Obsoletes:      %{legacy_product}-healthchecks < %{version}-%{release}
Summary:        Healthchecks
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    healthchecks
The service which displays launched services.

%package        plugins
Provides:       %{legacy_product}-plugins = %{version}-%{release}
Obsoletes:      %{legacy_product}-plugins < %{version}-%{release}
Summary:        Plugins
Requires:       %name-common  = %version-%release
AutoReqProv:    no
BuildArch:      noarch
%description    plugins
This package includes plugins that extend %{product_name} functionality.

%package sdk
Provides:       %{legacy_product}-sdk = %{version}-%{release}
Obsoletes:      %{legacy_product}-sdk < %{version}-%{release}
Summary:        Sdk
Requires:       %name-common = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description sdk
The service which allows integrating %{product_name} into your own web
application by using JavaScript SDK.

%package        management
Provides:       %{legacy_product}-management = %{version}-%{release}
Obsoletes:      %{legacy_product}-management < %{version}-%{release}
Summary:        Management
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    management
The service responsible for creating and managing several spaces.

%package        telegram
Provides:       %{legacy_product}-telegram = %{version}-%{release}
Obsoletes:      %{legacy_product}-telegram < %{version}-%{release}
Summary:        Telegram
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    telegram
The service which is used for receiving %{product_name} notifications via Telegram.

%package        ai
Provides:       %{legacy_product}-ai = %{version}-%{release}
Obsoletes:      %{legacy_product}-ai < %{version}-%{release}
Summary:        AI
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    ai
The REST API server for working with AI features. The service which
handles API requests related to AI.

%package        ai-worker
Provides:       %{legacy_product}-ai-worker = %{version}-%{release}
Obsoletes:      %{legacy_product}-ai-worker < %{version}-%{release}
Summary:        AI-Worker
Requires:       %name-common  = %version-%release
Requires:       aspnetcore-runtime-%{dotnet_version}
AutoReqProv:    no
BuildArch:      noarch
%description    ai-worker
The service for background tasks related with AI. It vectorizes documents
from the knowledge base for subsequent semantic search and performs
chat/message export.

%package        mcp
Provides:       %{legacy_product}-mcp = %{version}-%{release}
Obsoletes:      %{legacy_product}-mcp < %{version}-%{release}
Summary:        MCP
Requires:       %name-common  = %version-%release
Requires:       nodejs >= %{node_version}.0
AutoReqProv:    no
BuildArch:      noarch
%description    mcp
The server that operates using the Model Context Protocol, which provides AI
with functionality for working in %{product_name}.
