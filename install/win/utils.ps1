Param (
    [string]$FunctionName
)

# Generates a random string of the specified length.
function RandomString {
    param (
        [int]$Length
    )
    $Characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $Limit = 256 - (256 % $Characters.Length)  # bytes above it would bias the result
    $Buffer = [byte[]]::new(1)
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        return -join (1..$Length | ForEach-Object {
            do { $Rng.GetBytes($Buffer) } while ($Buffer[0] -ge $Limit)
            $Characters[$Buffer[0] % $Characters.Length]
        })
    } finally {
        $Rng.Dispose()
    }
}

# Secret MSI properties use " " as the "not set" placeholder.
function IsUnset {
    param (
        [string]$Value
    )
    return [string]::IsNullOrWhiteSpace($Value)
}

function IsLocalHost {
    param (
        [string]$HostName
    )
    return @('localhost', '127.0.0.1', '::1') -contains "$HostName".Trim()
}

# The package is 32-bit, so its keys live in the 32-bit registry view.
$RegistryRoot       = 'SOFTWARE\Ascensio System SIA'
$ProductKey         = "$RegistryRoot\ONLYOFFICE Apps"
$DatabaseSecretsKey = "$RegistryRoot\ONLYOFFICE Apps Database"
$AdministratorsOnlySddl = 'D:PAI(A;CI;KA;;;SY)(A;CI;KA;;;BA)'  # SYSTEM and Administrators, nothing inherited

# Opens (or creates) an HKLM key and leaves access to SYSTEM and Administrators only.
function OpenProtectedRegistryKey {
    param (
        [string]$SubKey,
        [switch]$Create
    )
    $ReadWrite = [Microsoft.Win32.RegistryKeyPermissionCheck]::ReadWriteSubTree
    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
    try {
        $Key = if ($Create) { $Base.CreateSubKey($SubKey, $ReadWrite) } else { $Base.OpenSubKey($SubKey, $ReadWrite) }
        if ($Key) {
            $Acl = [System.Security.AccessControl.RegistrySecurity]::new()
            $Acl.SetSecurityDescriptorSddlForm($AdministratorsOnlySddl, 'Access')
            $Key.SetAccessControl($Acl)
        }
        return $Key
    } finally {
        $Base.Close()
    }
}

# Secrets are written here, not from the Registry table: Windows Installer logs the value of every
# registry value it writes (RegAddValue), even for properties listed in MsiHiddenProperties.
$ProductSecrets = 'DB_PWD', 'AMQP_PWD', 'PS_DB_PWD', 'REDIS_PWD', 'DASHBOARDS_PWD', 'DOCUMENT_SERVER_JWT_SECRET', 'MACHINE_KEY', 'IDENTITY_ENCRYPTION_SECRET'
# Kept after uninstall, as their permanent components did, so that a reinstall reuses them.
$PermanentSecrets = 'MACHINE_KEY', 'IDENTITY_ENCRYPTION_SECRET'

function StoreProductSecrets {
    $Uninstall = (AI_GetMsiProperty REMOVE) -eq 'ALL'
    $Key = OpenProtectedRegistryKey $ProductKey -Create:(-not $Uninstall)
    if (-not $Key) { return }
    try {
        foreach ($Name in $ProductSecrets) {
            if (-not $Uninstall) { $Key.SetValue($Name, [string](AI_GetMsiProperty $Name)) }
            elseif ($PermanentSecrets -notcontains $Name) { $Key.DeleteValue($Name, $false) }
        }
    } finally {
        $Key.Close()
    }
}

# Superuser passwords of the bundled database servers. The key is not owned by the MSI,
# so a reinstall can still sign in after an uninstall.
function GetDatabaseSecret {
    param (
        [string]$Name
    )
    $Key = OpenProtectedRegistryKey $DatabaseSecretsKey
    if ($Key) { try { return $Key.GetValue($Name) } finally { $Key.Close() } }
}

function StoreDatabaseSecret {
    param (
        [string]$Name,
        [string]$Value
    )
    $Key = OpenProtectedRegistryKey $DatabaseSecretsKey -Create
    try { $Key.SetValue($Name, $Value) } finally { $Key.Close() }
}

function GetMySqlOdbcDriver {
    $Driver = Get-ChildItem 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI', 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like '*MySQL ODBC*' -and $_.PSChildName -notlike '*ANSI*' } |
        Select-Object -First 1 -ExpandProperty PSChildName
    return "$Driver"
}

# Returns $null when the server rejects the credentials.
function OpenOdbcConnection {
    param (
        [string]$ConnectionString
    )
    $Connection = New-Object System.Data.Odbc.OdbcConnection($ConnectionString)
    try {
        $Connection.Open()
        return $Connection
    } catch {
        $Connection.Dispose()
        return $null
    }
}

# Signs in with the first password that works; returns the connection and that password.
function ConnectWithFirstPassword {
    param (
        [string]$ConnectionString,
        [string[]]$Passwords
    )
    foreach ($Password in $Passwords | Where-Object { -not (IsUnset $_) } | Select-Object -Unique) {
        $Connection = OpenOdbcConnection "$ConnectionString;PWD=$Password;"
        if ($Connection) {
            return @{ Connection = $Connection; Password = $Password }
        }
    }
}

function ConnectMySqlRoot {
    param (
        [string[]]$Passwords
    )
    return ConnectWithFirstPassword "DRIVER={$(GetMySqlOdbcDriver)};SERVER=127.0.0.1;PORT=$(AI_GetMsiProperty DB_PORT);USER=root" $Passwords
}

function ConnectPostgres {
    param (
        [string[]]$Passwords
    )
    return ConnectWithFirstPassword "Driver={PostgreSQL Unicode};Server=$(AI_GetMsiProperty PS_DB_HOST);Port=$(AI_GetMsiProperty PS_DB_PORT);Database=postgres;Uid=postgres" $Passwords
}

function InvokeOdbcNonQuery {
    param (
        $Connection,
        [string[]]$Statements
    )
    $Cmd = $Connection.CreateCommand()
    try {
        foreach ($Statement in $Statements) {
            $Cmd.CommandText = $Statement
            [void]$Cmd.ExecuteNonQuery()
        }
    } finally {
        $Cmd.Dispose()
    }
}

# Helper function to replaces or add a configuration parameter in the provided content.
function UpdateConfig {
    param (
        [string]$Content,
        [string]$Pattern,
        [string]$Replacement
    )

    $Lines = $Content -split "`n"
    $Found = $false

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match "^$Pattern.*") {
            $Lines[$i] = $Replacement
            $Found = $true
            break
        }
    }

    if (-not $Found) {
        $Lines += $Replacement
    }

    return $Lines -join "`n"
}

# Helper function to read file content.
function ReadFileContent {
    param (
        [string]$FilePath
    )
    if (Test-Path $FilePath) {
        return Get-Content -Path $FilePath -Raw
    } else {
        Write-Output "File not found: $FilePath"
        return $null
    }
}

# Helper function to extract path from content using regex.
function ExtractPath {
    param (
        [string]$Content,
        [string]$RegexPattern
    )
    if ($Content -match $RegexPattern) {
        return $matches[1]
    } else {
        return ""
    }
}

# MSI AppSearch can redirect Program Files paths in a 32-bit package.
function GetDocumentServerInstallLocation {
    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $Key = $null
    try {
        $Key = $Base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ONLYOFFICE DocumentServer_is1')
        if ($Key) { return $Key.GetValue('InstallLocation') }
    } finally {
        if ($Key) { $Key.Close() }
        $Base.Close()
    }
}

# Applies Docs registry search results to Apps properties.
function ApplyInstalledDocumentServerSettings {
    $InstalledVersion = AI_GetMsiProperty DOCS_INSTALLED_VERSION
    if (-not $InstalledVersion) { return }

    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    try {
        $DocsKey = $Base.CreateSubKey('SOFTWARE\ONLYOFFICE\DocumentServer')
        $DocsPort = AI_GetMsiProperty DOCUMENT_SERVER_PORT
        $DocsKey.SetValue('DsPort', $DocsPort, [Microsoft.Win32.RegistryValueKind]::String)
    } catch { Write-Warning "Failed to set DocumentServer port in registry: $_" }
    finally { if ($DocsKey) { $DocsKey.Close() }; $Base.Close() }

    $RegistryDocsDir = GetDocumentServerInstallLocation
    if ($RegistryDocsDir) {
        AI_SetMsiProperty DOCS_INSTALL_LOCATION $RegistryDocsDir
    }

    $EditionSuffix = @{ community = ''; enterprise = ' EE'; developer = ' DE' }[(AI_GetMsiProperty ENVIRONMENT)]
    $SameEdition = (AI_GetMsiProperty DOCS_INSTALLED_DISPLAY_NAME) -match "^ONLYOFFICE Document Server$EditionSuffix(?:\s+\d|$)"
    $SkipDocsInstall = $false
    try { $SkipDocsInstall = $SameEdition -and [version]$InstalledVersion -ge [version](AI_GetMsiProperty DS_VERSION) }
    catch { Write-Warning "Invalid DocumentServer version: installed=$InstalledVersion" }
    AI_SetMsiProperty DOCUMENT_SERVER_INSTALL_NONE ([string][int]$SkipDocsInstall)

    # The secret DOCS_* properties are declared with a " " placeholder so they can be hidden from the log.
    if ($Value = AI_GetMsiProperty DOCS_DBHOST) { AI_SetMsiProperty PS_DB_HOST $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBNAME) { AI_SetMsiProperty PS_DB_NAME $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBPORT) { AI_SetMsiProperty PS_DB_PORT $Value }
    if (-not (IsUnset ($Value = AI_GetMsiProperty DOCS_DBPWD))) { AI_SetMsiProperty PS_DB_PWD $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBUSER) { AI_SetMsiProperty PS_DB_USER $Value }
    if ($Value = AI_GetMsiProperty DOCS_JWTENABLED) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_ENABLED $Value
        AI_SetMsiProperty JWT_ENABLED $Value
    }
    if ($Value = AI_GetMsiProperty DOCS_JWTHEADER) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_HEADER $Value
        AI_SetMsiProperty JWT_HEADER $Value
    }
    if (-not (IsUnset ($Value = AI_GetMsiProperty DOCS_JWTSECRET))) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_SECRET $Value
        AI_SetMsiProperty JWT_SECRET $Value
    }
    if ($Value = AI_GetMsiProperty DOCS_RABBITMQHOST) { AI_SetMsiProperty AMQP_HOST $Value }
    if ($Value = AI_GetMsiProperty DOCS_RABBITMQPROTO) { AI_SetMsiProperty AMQP_PROTOCOL $Value }
    if (-not (IsUnset ($Value = AI_GetMsiProperty DOCS_RABBITMQPWD))) { AI_SetMsiProperty AMQP_PWD $Value }
    if ($Value = AI_GetMsiProperty DOCS_RABBITMQUSER) { AI_SetMsiProperty AMQP_USER $Value }
    if ($Value = AI_GetMsiProperty DOCS_REDISHOST) { AI_SetMsiProperty REDIS_HOST $Value }

    try {
        $DocsInstallDir = AI_GetMsiProperty DOCS_INSTALL_LOCATION
        if (-not $DocsInstallDir) {
            $DocsInstallDir = Join-Path (AI_GetMsiProperty ProgramFiles64Folder) 'ONLYOFFICE\DocumentServer'
        }
        $DocsConfigPath = Join-Path $DocsInstallDir 'config\local.json'
        if (Test-Path -LiteralPath $DocsConfigPath -PathType Leaf) {
            $DocsLicensePath = (Get-Content -LiteralPath $DocsConfigPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).license.license_file
            if ($DocsLicensePath) {
                AI_SetMsiProperty LICENSE_PATH $DocsLicensePath
            }
        }
    }
    catch { Write-Warning 'Unable to read the existing DocumentServer license configuration.' }

    Write-Output 'Existing DocumentServer settings applied.'
}

# Tests the connection to PostgreSQL using ODBC.
function TestPostgreSqlConnection {
    AI_SetMsiProperty PostgreSqlConnectionError ""

    $Server   = AI_GetMsiProperty PS_DB_HOST
    $Port     = AI_GetMsiProperty PS_DB_PORT
    $Database = AI_GetMsiProperty PS_DB_NAME
    $Uid      = AI_GetMsiProperty PS_DB_USER
    $Pwd      = AI_GetMsiProperty PS_DB_PWD

    $ConnectionString = "Driver={PostgreSQL Unicode};Server=$Server;Port=$Port;Database=$Database;Uid=$Uid;Pwd=$Pwd;"
    $Connection = New-Object System.Data.Odbc.OdbcConnection($ConnectionString)

    try {
        $Connection.Open()
        Write-Output "Connection to PostgreSQL is successful."
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Output "An error occurred while trying to connect to PostgreSQL:"
        Write-Output $ErrorMessage
        AI_SetMsiProperty PostgreSqlConnectionError $ErrorMessage
    }
    finally {
        if ($Connection -and $Connection.State -eq 'Open') {
            $Connection.Close()
        }
    }
}

# Tests the connection to MySQL using ODBC.
function TestSqlConnection {
    $Server   = AI_GetMsiProperty DB_HOST
    $Port     = AI_GetMsiProperty DB_PORT
    $Database = AI_GetMsiProperty DB_NAME
    $Uid      = AI_GetMsiProperty DB_USER
    $Pwd      = AI_GetMsiProperty DB_PWD

    $MySqlDriver = GetMySqlOdbcDriver
    AI_SetMsiProperty MYSQLODBCDRIVER $MySqlDriver

    $ConnectionString = "DRIVER={$MySqlDriver};SERVER=$Server;PORT=$Port;USER=$Uid;PASSWORD=$Pwd;"
    $Connection = New-Object System.Data.Odbc.OdbcConnection($ConnectionString)

    try {
        $Connection.Open()
        Write-Output "Connection to MySQL is successful."
    }
    catch {
        $ErrorMessage = $_.Exception.Message
        Write-Output "An error occurred while trying to connect to MySQL:"
        Write-Output $ErrorMessage
        AI_SetMsiProperty SqlConnectionError $ErrorMessage
    }
    finally {
        if ($Connection -and $Connection.State -eq 'Open') {
            $Connection.Close()
        }
    }
}

# Superuser passwords the bundled prerequisites start with: MySQL from "MySQL Server Installer Runner.iss",
# PostgreSQL from --superpassword in Apps.aip. SecureDatabaseSuperusers replaces them.
$MySqlBootstrapRootPassword  = 'root'
$PostgreSqlBootstrapPassword = 'postgres'
$ApplicationDbUser           = 'onlyoffice_user'

# The prefix satisfies the default MySQL password policy.
function NewDatabasePassword {
    return 'Aa1_' + (RandomString -Length 28)
}

# Gives the application its own MySQL account limited to its database.
function CreateMySqlApplicationAccount {
    $DbName   = AI_GetMsiProperty DB_NAME
    $DbPwd    = AI_GetMsiProperty DB_PWD
    $UsesRoot = (AI_GetMsiProperty DB_USER) -eq 'root'

    $IsRemote      = -not (IsLocalHost (AI_GetMsiProperty DB_HOST))
    $HasOwnAccount = -not $UsesRoot -and -not (IsUnset $DbPwd)
    if ($IsRemote -or $HasOwnAccount) {
        Write-Output "Using the provided MySQL account."
        return
    }
    # The name is interpolated into SQL.
    if ($DbName -notmatch '^[A-Za-z0-9_]+$') { throw "DB_NAME '$DbName' is not a plain identifier." }

    $RootPasswords = @((GetDatabaseSecret MYSQL_ROOT_PWD), $MySqlBootstrapRootPassword)
    if ($UsesRoot) { $RootPasswords = @($DbPwd) + $RootPasswords }  # an earlier installation or the command line

    $Login = ConnectMySqlRoot $RootPasswords
    if (-not $Login) {
        Write-Output "Unable to sign in to the local MySQL server as root; the MySQL account must be entered manually."
        return
    }

    try {
        $AppPwd = NewDatabasePassword
        InvokeOdbcNonQuery $Login.Connection @(foreach ($AccountHost in 'localhost', '127.0.0.1') {
            "CREATE USER IF NOT EXISTS '$ApplicationDbUser'@'$AccountHost' IDENTIFIED BY '$AppPwd'"
            "ALTER USER '$ApplicationDbUser'@'$AccountHost' IDENTIFIED BY '$AppPwd'"
            "GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$ApplicationDbUser'@'$AccountHost'"
        })
        # The configuration no longer holds the root password, so keep it for administrators.
        StoreDatabaseSecret MYSQL_ROOT_PWD $Login.Password

        AI_SetMsiProperty DB_USER $ApplicationDbUser
        AI_SetMsiProperty DB_PWD $AppPwd
        Write-Output "MySQL account '$ApplicationDbUser' has access to database '$DbName' only."
    } finally {
        $Login.Connection.Close()
    }
}

# Replaces a bootstrap superuser password. The new one is stored first, so it can never be lost.
function ReplaceBootstrapPassword {
    param (
        $Login,
        [string]$SecretName,
        [string]$AlterStatement  # {0} is the new password
    )
    if (-not $Login) { return }
    try {
        $Password = NewDatabasePassword
        StoreDatabaseSecret $SecretName $Password
        InvokeOdbcNonQuery $Login.Connection ($AlterStatement -f $Password)
        Write-Output "The bootstrap password ($SecretName) was replaced with a random one."
    } catch {
        Write-Warning "Unable to replace the bootstrap password ($SecretName): $($_.Exception.Message)"
    } finally {
        $Login.Connection.Close()
    }
}

# Runs after InstallFinalize, so a rolled back update never depends on a changed password.
# Skipped while the application itself signs in as the superuser.
function SecureDatabaseSuperusers {
    if ((IsLocalHost (AI_GetMsiProperty DB_HOST)) -and (AI_GetMsiProperty DB_USER) -ne 'root') {
        ReplaceBootstrapPassword (ConnectMySqlRoot $MySqlBootstrapRootPassword) MYSQL_ROOT_PWD "ALTER USER 'root'@'localhost' IDENTIFIED BY '{0}'"
    }
    if ((IsLocalHost (AI_GetMsiProperty PS_DB_HOST)) -and (AI_GetMsiProperty PS_DB_USER) -ne 'postgres') {
        ReplaceBootstrapPassword (ConnectPostgres $PostgreSqlBootstrapPassword) POSTGRES_PWD "ALTER USER postgres WITH PASSWORD '{0}'"
    }
}

# Configures MySQL settings by updating my.ini and setting up the application account.
function MySQLConfigure {
    $DataDir = (AI_GetMsiProperty "ProgramFiles64Folder") + "/MySQL/MySQL Server 8.4/data"

    Write-Output "MySQLConfigure: DataDir $DataDir"

    try {
        $Service = Get-Service -Name "MySQL84" -ErrorAction Stop

        if ($Service.Status -eq 'Running') {
            CreateMySqlApplicationAccount
        } else {
            Write-Output "MySQL service is not running."
        }
    }
    catch {
        Write-Output "An error occurred while accessing the MySQL service:"
        Write-Output $_.Exception.Message
    }

    $ParametersToUpdate = @{
        "sql-mode"             = "NO_ENGINE_SUBSTITUTION"
        "max_connections"      = "1000"
        "max_allowed_packet"   = "1048576000"
        "group_concat_max_len" = "2048"
        "character_set_server" = "utf8"
        "collation_server"     = "utf8_general_ci"
    }

    $IniFilePath   = Join-Path $DataDir "my.ini"
    $Lines         = Get-Content -Path $IniFilePath
    $UpdatedParams = @{}

    $UpdatedLines = foreach ($Line in $Lines) {
        foreach ($Param in $ParametersToUpdate.Keys) {
            if ($Line -match "^$Param\s*=") {
                $Line = "$Param=" + $ParametersToUpdate[$Param]
                $UpdatedParams[$Param] = $true
                break
            }
        }
        $Line
    }

    foreach ($Param in $ParametersToUpdate.Keys) {
        if (-not $UpdatedParams.ContainsKey($Param)) {
            $UpdatedLines += "$Param=" + $ParametersToUpdate[$Param]
        }
    }

    $UpdatedLines | Set-Content -Path $IniFilePath
}

# A silent install runs the Docs prerequisite before the MSI, so Docs gets the default (empty) database
# password. Gives the installed Docs the password of its database user and restarts its services.
function SyncDocumentServerDbPassword {
    param (
        [string]$DbUser,
        [string]$DbPwd
    )
    $DocsDir = GetDocumentServerInstallLocation
    if (-not $DocsDir) { return }
    $LocalJson = Join-Path $DocsDir 'config\local.json'
    if (-not (Test-Path -LiteralPath $LocalJson -PathType Leaf)) { return }

    $DocsDb = (Get-Content -LiteralPath $LocalJson -Raw | ConvertFrom-Json).services.CoAuthoring.sql
    if ($DocsDb.dbUser -ne $DbUser -or $DocsDb.dbPass -eq $DbPwd) { return }

    $JsonPwd = (ConvertTo-Json $DbPwd -Compress) -replace '^"|"$', ''
    $Content = [regex]::Replace([IO.File]::ReadAllText($LocalJson), '("dbPass"\s*:\s*")[^"]*', { param($Match) $Match.Groups[1].Value + $JsonPwd })
    [IO.File]::WriteAllText($LocalJson, $Content, (New-Object Text.UTF8Encoding($false)))

    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    try {
        $Key = $Base.OpenSubKey('SOFTWARE\ONLYOFFICE\DocumentServer', $true)
        if ($Key) { try { $Key.SetValue('DbPwd', $DbPwd) } finally { $Key.Close() } }
    } finally {
        $Base.Close()
    }

    Get-Service DsDocServiceSvc, DsConverterSvc -ErrorAction SilentlyContinue | Restart-Service -Force
    Write-Output "DocumentServer now uses the password of database user '$DbUser'."
}

# For the same reason the Docs installer could not create its tables: its database user did not exist yet.
function CreateDocumentServerSchema {
    $DocsDir = GetDocumentServerInstallLocation
    if (-not $DocsDir) { return }
    $Schema = Join-Path $DocsDir 'server\schema\postgresql\createdb.sql'
    if (-not (Test-Path -LiteralPath $Schema -PathType Leaf)) { return }

    $Conn = OpenOdbcConnection "Driver={PostgreSQL Unicode};Server=$(AI_GetMsiProperty PS_DB_HOST);Port=$(AI_GetMsiProperty PS_DB_PORT);Database=$(AI_GetMsiProperty PS_DB_NAME);Uid=$(AI_GetMsiProperty PS_DB_USER);Pwd=$(AI_GetMsiProperty PS_DB_PWD)"
    if (-not $Conn) { return }
    try {
        $Cmd = $Conn.CreateCommand()
        $Cmd.CommandText = "SELECT COUNT(*) FROM pg_tables WHERE schemaname = 'public' AND tablename = 'task_result'"
        if ([int]$Cmd.ExecuteScalar() -gt 0) { return }

        InvokeOdbcNonQuery $Conn ([IO.File]::ReadAllText($Schema))
        Write-Output "DocumentServer database tables created."
    } finally {
        $Conn.Close()
    }
}

# Configures PostgreSQL by creating the database and user if they do not exist.
function PostgreSqlConfigure {
    $DbUser = AI_GetMsiProperty PS_DB_USER
    $DbPwd  = AI_GetMsiProperty PS_DB_PWD
    $DbName = AI_GetMsiProperty PS_DB_NAME
    $DbPort = AI_GetMsiProperty PS_DB_PORT
    $DbHost = AI_GetMsiProperty PS_DB_HOST

    try {
        $Conn = (ConnectPostgres (GetDatabaseSecret POSTGRES_PWD), $PostgreSqlBootstrapPassword).Connection
        if (-not $Conn) {
            Write-Output "Unable to sign in to PostgreSQL as postgres; the account must be entered manually."
            return
        }

        # No password was provided and none was taken from an installed Docs.
        $GeneratedPwd = IsUnset $DbPwd
        if ($GeneratedPwd) { $DbPwd = NewDatabasePassword }

        $Cmd = $Conn.CreateCommand()

        $Cmd.CommandText = "SELECT 1 FROM pg_database WHERE datname = '$DbName';"
        $DbExists = $Cmd.ExecuteScalar()

        if (-not $DbExists) {
            $Cmd.CommandText = "CREATE DATABASE $DbName;"
            $Cmd.ExecuteNonQuery()
            Write-Output "Database '$DbName' created successfully."
        } else {
            Write-Output "Database '$DbName' already exists."
        }

        $Cmd.CommandText = "SELECT 1 FROM pg_roles WHERE rolname = '$DbUser';"
        $UserExists = $Cmd.ExecuteScalar()

        if (-not $UserExists) {
            $Cmd.CommandText = "CREATE USER $DbUser WITH ENCRYPTED PASSWORD '$DbPwd';"
            $Cmd.ExecuteNonQuery()
            Write-Output "User '$DbUser' created successfully."
        } elseif ($GeneratedPwd) {
            # The generated password must match the existing user.
            $Cmd.CommandText = "ALTER USER $DbUser WITH ENCRYPTED PASSWORD '$DbPwd';"
            $Cmd.ExecuteNonQuery()
            Write-Output "User '$DbUser' already exists; its password was replaced."
        } else {
            Write-Output "User '$DbUser' already exists."
        }

        $Cmd.CommandText = "GRANT ALL PRIVILEGES ON DATABASE $DbName TO $DbUser;"
        $Cmd.ExecuteNonQuery()
        Write-Output "Granted privileges on database '$DbName' to user '$DbUser'."

        if ($GeneratedPwd) { AI_SetMsiProperty PS_DB_PWD $DbPwd }
        SyncDocumentServerDbPassword $DbUser $DbPwd
        CreateDocumentServerSchema
    }
    catch {
        Write-Output "An error occurred while configuring PostgreSQL:"
        Write-Output $_.Exception.Message
    }
    finally {
        if ($Conn -and $Conn.State -eq 'Open') {
            $Conn.Close()
        }
    }
}

# Sets a random JWT secret property for the document server.
function SetDocumentServerJWTSecretProp {
    $JwtSecret = RandomString -Length 30
    AI_SetMsiProperty JWT_SECRET $JwtSecret
}

# Sets the MACHINE_KEY MSI property based on existing configuration or generates a new one.
function SetMachineKey {
    $AppDir = AI_GetMsiProperty APPDIR
    $JsonFilePath = Join-Path -Path $AppDir -ChildPath "config\appsettings.production.json"
    $MachineKey = ""

    if (Test-Path -Path $JsonFilePath) {
        $JsonContent = Get-Content -Path $JsonFilePath -Raw | ConvertFrom-Json
        $MachineKey = $JsonContent.core.machinekey
    }

    if ([string]::IsNullOrEmpty($MachineKey)) {
        $MachineKey = RandomString -Length 32
        Write-Output "MACHINE_KEY is set to a new random value."
    } else {
        Write-Output "MACHINE_KEY is taken from the existing configuration."
    }

    AI_SetMsiProperty MACHINE_KEY $MachineKey
}

# Sets a random DASHBOARDS_PWD property.
function SetDashboardsPwd {
    $DashboardsPwd = RandomString -Length 20
    AI_SetMsiProperty DASHBOARDS_PWD $DashboardsPwd
}

# Reads the Identity encryption key from the service wrappers of the installed version.
function GetInstalledIdentityEncryptionSecret {
    $AppDir = AI_GetMsiProperty APPDIR
    if (IsUnset $AppDir) { return }

    foreach ($Name in 'Identity.Authorization.xml', 'Identity.Registration.xml') {
        $Path = Join-Path $AppDir "tools\$Name"
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { continue }
        try {
            $Value = ([xml](Get-Content -LiteralPath $Path -Raw)).service.env |
                Where-Object name -eq 'SPRING_APPLICATION_ENCRYPTION_SECRET' |
                Select-Object -First 1 -ExpandProperty value
            # A wrapper that was never filled in still holds the {IDENTITY_ENCRYPTION_SECRET} placeholder.
            if (-not (IsUnset $Value) -and $Value -notmatch '^\{.*\}$') { return $Value }
        } catch {
            Write-Warning "Unable to read $Path."
        }
    }
}

# Runs only when the registry holds no key. An update must keep the installed key: a new one would make
# the data encrypted by Identity unreadable, so without it the update stops (AbortMissingIdentityEncryptionSecret).
function SetIdentityEncryptionSecret {
    if (-not (AI_GetMsiProperty OLDPRODUCTS)) {
        AI_SetMsiProperty IDENTITY_ENCRYPTION_SECRET (RandomString -Length 32)
        Write-Output "IDENTITY_ENCRYPTION_SECRET is set to a new random value."
    } elseif ($InstalledSecret = GetInstalledIdentityEncryptionSecret) {
        AI_SetMsiProperty IDENTITY_ENCRYPTION_SECRET $InstalledSecret
        Write-Output "IDENTITY_ENCRYPTION_SECRET is taken from the installed version."
    } else {
        AI_SetMsiProperty IDENTITY_ENCRYPTION_SECRET_MISSING "1"
        Write-Output "IDENTITY_ENCRYPTION_SECRET of the installed version was not found; the update is stopped."
    }
}

# Function to set up OpenSearch.
function OpenSearchSetup {
    $AppDir = AI_GetMsiProperty APPDIR
    $AppIndexDir = Join-Path $AppDir "Data\Index\v3.5.0\"
    $LogsDir     = Join-Path $AppDir "Logs\"
    $OpenSearchDashboardsYml = "C:\OpenSearchStack\opensearch-dashboards-3.5.0\config\opensearch_dashboards.yml"

    # Check if the index directory exists and set NEED_REINDEX_OPENSEARCH property if it doesn't.
    if (-not (Test-Path $AppIndexDir)) {
        AI_SetMsiProperty NEED_REINDEX_OPENSEARCH "TRUE"
    }

    # Create necessary directories.
    New-Item -Path $AppIndexDir -ItemType Directory -Force | Out-Null
    New-Item -Path $LogsDir -ItemType Directory -Force | Out-Null

    # Modify OpenSearch configuration.
    $ConfigFilePath = "C:\OpenSearch\config\opensearch.yml"
    $FileContent = Get-Content -Path $ConfigFilePath -Raw
   
    $FileContent = UpdateConfig $FileContent "indices.fielddata.cache.size:.*" "indices.fielddata.cache.size: 30%"
    $FileContent = UpdateConfig $FileContent "indices.memory.index_buffer_size:.*" "indices.memory.index_buffer_size: 30%"
    $FileContent = UpdateConfig $FileContent "#?path.data:.*" "path.data: $AppIndexDir"
    $FileContent = UpdateConfig $FileContent "#?path.logs:.*" "path.logs: $LogsDir"
    $FileContent = UpdateConfig $FileContent "plugins.security.disabled:.*" "plugins.security.disabled: true"

    Set-Content -Path $ConfigFilePath -Value $FileContent

    # Modify JVM options.
    $JvmOptionsPath = "C:\OpenSearch\config\jvm.options"
    $FileContent = Get-Content -Path $JvmOptionsPath -Raw

    $FileContent = UpdateConfig $FileContent "-Xms.*" "-Xms4g"
    $FileContent = UpdateConfig $FileContent "-Xmx.*" "-Xmx4g"
    $FileContent = UpdateConfig $FileContent "-Dlog4j2.formatMsgNoLookups.*" "-Dlog4j2.formatMsgNoLookups=true"

    Set-Content -Path $JvmOptionsPath -Value $FileContent

    # Modify OpenSearch Dashboards configuration.
    if (Test-Path $OpenSearchDashboardsYml) {
        Set-Content -Path $OpenSearchDashboardsYml -Value "" -Force
    } else {
        Write-Output "File doesn't exist: $OpenSearchDashboardsYml"
    }

    $FileContent = Get-Content -Path $OpenSearchDashboardsYml -Raw

    $FileContent = UpdateConfig $FileContent "opensearch.hosts:.*" "opensearch.hosts: [http://localhost:9200]"
    $FileContent = UpdateConfig $FileContent "server.host:.*" "server.host: 127.0.0.1"
    $FileContent = UpdateConfig $FileContent "server.basePath:.*" "server.basePath: /dashboards"
    $FileContent = UpdateConfig $FileContent "server.rewriteBasePath:.*" "server.rewriteBasePath: true"

    Set-Content -Path $OpenSearchDashboardsYml -Value $FileContent
}

# Sets up Redis by disabling saving and rewriting the configuration.
function RedisSetup {
    try {
        # Path to redis-cli.exe
        $RedisCliPath = "C:\Program Files\Redis-Windows\redis-cli.exe"
        
        # Disable saving by setting 'save ""'
        & $RedisCliPath 'config' 'set' 'save' '""'

        # Rewrite the configuration
        & $RedisCliPath 'config' 'rewrite'
    } catch {
        Write-Error "An error occurred: $($_.Exception.Message)"
    }
}

# Sets AppDir with forward slash
function SetAppDirWithForwardSlash {
    $AppDir = AI_GetMsiProperty APPDIR
    $AppDirForwardSlash = $AppDir -replace '\\', '/'

    AI_SetMsiProperty APPDIR_FORWARD_SLASH $AppDirForwardSlash
}

function MigrateProductRegistry {
    $LegacyKey = "HKLM\Software\Ascensio System SIA\ONLYOFFICE DocSpace"
    $AppsKey = "HKLM\Software\Ascensio System SIA\ONLYOFFICE Apps"
    $LegacyPath = "Registry::$LegacyKey"
    $AppsPath = "Registry::$AppsKey"

    if (-not (Test-Path -LiteralPath $LegacyPath)) {
        return
    }

    if (Test-Path -LiteralPath $AppsPath) {
        return
    }

    try {
        Rename-Item -LiteralPath $LegacyPath -NewName "ONLYOFFICE Apps" -ErrorAction Stop
        Write-Output "The product registry key was renamed to ONLYOFFICE Apps."
        return
    }
    catch {
        Write-Output "Unable to rename the product registry key. Falling back to a recursive copy."
    }

    try {
        & "$env:SystemRoot\System32\reg.exe" copy $LegacyKey $AppsKey /s /f | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "reg.exe exited with code $LASTEXITCODE"
        }
        Write-Output "The legacy product registry tree was copied to ONLYOFFICE Apps."
    }
    catch {
        Write-Warning "Unable to migrate the product registry key: $($_.Exception.Message)"
    }
}

# Function to move configurations and manage files.
function MoveConfigs {
    # Define source and target paths.
    $AppDir = AI_GetMsiProperty APPDIR
    $SourceFolder = Join-Path $AppDir "nginx\conf"
    $TargetFolder = "C:\OpenResty\conf\"
    $NginxFolder = Join-Path $AppDir "nginx"
    $ConfigSslFile = Join-Path $TargetFolder "onlyoffice-proxy-ssl.conf.tmpl"
    $ConfigFile = Join-Path $TargetFolder "onlyoffice-proxy.conf"
    $SslScriptDir = Join-Path $AppDir "sbin\"
    $SslScriptPath = Join-Path $AppDir "sbin\apps-ssl-setup.ps1"
    $FluentBitSourceFile = Join-Path $AppDir "config\fluent-bit.conf"
    $FluentBitDstFolder = "C:\OpenSearchStack\fluent-bit-3.2.4-win64\conf\"

    $SslCertPath = ''
    $SslCertKeyPath = ''

    # Extract SSL certificate and key paths if config file exists.
    if (Test-Path $ConfigFile) {
        $Content = ReadFileContent $ConfigFile
        $SslCertPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate\s+(.*?);"
        $SslCertKeyPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate_key\s+(.*?);"
        $DomainName = AI_GetMsiProperty DOMAIN_NAME
    } else {
        Write-Output "Configuration file not found!"
    }

    # Reuse Docs SSL when Apps has no certificate configured.
    if (((AI_GetMsiProperty DOCUMENT_SERVER_INSTALL_NONE) -eq '1') -and
        [string]::IsNullOrWhiteSpace($SslCertPath)) {
        $DocsDir = AI_GetMsiProperty DOCS_INSTALL_LOCATION
        $RegistryDocsDir = GetDocumentServerInstallLocation
        if ($RegistryDocsDir) { $DocsDir = $RegistryDocsDir }
        if (-not $DocsDir) { throw 'DocumentServer InstallLocation not found.' }

        $DocsConfig = Join-Path $DocsDir 'nginx\conf\ds.conf'
        if (Test-Path -LiteralPath $DocsConfig -PathType Leaf) {
            $Content = ReadFileContent $DocsConfig
            $SslCertPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate\s+(.*?);"
            $SslCertKeyPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate_key\s+(.*?);"
            $DomainName = AI_GetMsiProperty DOMAIN_NAME

            if (-not [string]::IsNullOrWhiteSpace($SslCertPath) -and
                -not [string]::IsNullOrWhiteSpace($SslCertKeyPath)) {
                $DocsSslScript = Join-Path $DocsDir 'bin\documentserver-letsencrypt.ps1'
                if (Test-Path -LiteralPath $DocsSslScript -PathType Leaf) {
                    & $DocsSslScript -d
                } else {
                    Write-Output "DocumentServer SSL setup script not found: $DocsSslScript. Skipping SSL reuse."
                    $SslCertPath = $null
                    $SslCertKeyPath = $null
                }
            }
        } else {
            Write-Output "DocumentServer config not found: $DocsConfig"
        }
    }

    # Remove existing onlyoffice* config files before copying.
    Get-ChildItem -Path $TargetFolder -Filter "onlyoffice*" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

    # Move nginx configuration files.
    if (Test-Path $SourceFolder) {
        # Ensure target folder exists.
        if (-not (Test-Path $TargetFolder)) {
            New-Item -ItemType Directory -Path $TargetFolder | Out-Null
        }

        # Copy files and folders from source to target.
        Get-ChildItem -Path $SourceFolder -Recurse | ForEach-Object {
            $DestPath = $_.FullName.Replace($SourceFolder, $TargetFolder)
            if ($_.PSIsContainer) {
                if (-not (Test-Path $DestPath)) {
                    New-Item -ItemType Directory -Path $DestPath | Out-Null
                }
            } else {
                Copy-Item -Path $_.FullName -Destination $DestPath
            }
        }

        # Delete source folder.
        Remove-Item -Path $NginxFolder -Recurse -Force
        Write-Output "Files and folders moved, and source folder deleted."
    } else {
        Write-Output "Source folder does not exist."
    }

    # Run the SSL setup script if paths are valid.
    if ((Test-Path $ConfigSslFile) -and ($SslCertPath) -and ($SslCertKeyPath)) {
        Set-Location $SslScriptDir
        $PsCommand = "& '$SslScriptPath' -f $DomainName $SslCertPath $SslCertKeyPath"
        try {
            Invoke-Expression $PsCommand
        } catch {
            Write-Warning "SSL setup skipped: $($_.Exception.Message)"
        }
    } else {
        Write-Output "SSL script not executed. Missing paths or ConfigSslFile."
    }

    # Manage Fluent Bit configuration.
    $FluentBitConfPath = Join-Path $FluentBitDstFolder "fluent-bit.conf"
    if (Test-Path $FluentBitConfPath) {
        Remove-Item -Path $FluentBitConfPath -Force
    }
    if (Test-Path $FluentBitSourceFile) {
        Move-Item -Path $FluentBitSourceFile -Destination $FluentBitDstFolder
    }

    if ((AI_GetMsiProperty DOCUMENT_SERVER_INSTALL_NONE) -eq '1') {
        $DocsDir = GetDocumentServerInstallLocation
        if (-not $DocsDir) { throw 'DocumentServer InstallLocation not found.' }

        $DocsConfig = Join-Path $DocsDir 'nginx\conf\ds.conf'
        if (-not (Test-Path -LiteralPath $DocsConfig)) { throw "DocumentServer config not found: $DocsConfig" }
        $Content = [IO.File]::ReadAllText($DocsConfig)
        $ListenPattern = '(?m)^([ \t]*listen[ \t]+(?:0\.0\.0\.0|\[::\]):)\d+'
        if ($Content -notmatch $ListenPattern) { throw "DocumentServer listen directive not found: $DocsConfig" }
        $DocsPort = AI_GetMsiProperty DOCUMENT_SERVER_PORT
        $UpdatedContent = $Content -replace $ListenPattern, ('${1}' + $DocsPort)
        if ($UpdatedContent -cne $Content) {
            [IO.File]::WriteAllText($DocsConfig, $UpdatedContent, (New-Object Text.UTF8Encoding($false)))
        }
        Restart-Service -Name DsProxySvc -Force -ErrorAction Stop
        Write-Output "DocumentServer port set to $DocsPort and DsProxySvc restarted."
    }

    Write-Output "Script execution completed."
}


if (Get-Command -Name $FunctionName -CommandType Function -ErrorAction SilentlyContinue) {
    # Call the function dynamically
    & $FunctionName
} else {
    Write-Error "Function '$FunctionName' is not defined."
}
