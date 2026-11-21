Param (
    [string]$FunctionName
)

# Generates a random string of the specified length.
function RandomString {
    param (
        [int]$Length
    )
    $Characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $Limit = 256 - (256 % $Characters.Length)  # bytes at or above the limit are skipped to keep the choice uniform
    $Buffer = New-Object byte[] 1
    $Generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $RandomString = ''
    try {
        while ($RandomString.Length -lt $Length) {
            $Generator.GetBytes($Buffer)
            if ($Buffer[0] -lt $Limit) {
                $RandomString += $Characters[$Buffer[0] % $Characters.Length]
            }
        }
    } finally {
        $Generator.Dispose()
    }
    return $RandomString
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

# The newest of the <name>-<version> folders matching Filter, ordered by version so 3.10.0 comes after 3.5.0; the OpenSearchStack.aip setup script repeats this lookup.
function GetNewestVersionedFolder([string]$Root, [string]$Filter) {
    Get-ChildItem -LiteralPath $Root -Directory -Filter $Filter -ErrorAction SilentlyContinue |
        Sort-Object { ($_.Name -replace '^\D*(\d+(\.\d+)+).*$', '$1') -as 'System.Version' } | Select-Object -Last 1
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

    if ($Value = AI_GetMsiProperty DOCS_DBHOST) { AI_SetMsiProperty PS_DB_HOST $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBNAME) { AI_SetMsiProperty PS_DB_NAME $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBPORT) { AI_SetMsiProperty PS_DB_PORT $Value }
    # The secret properties hold a blank placeholder so the log hides them, which here means Docs has no value.
    if ($Value = (AI_GetMsiProperty DOCS_DBPWD).Trim()) { AI_SetMsiProperty PS_DB_PWD $Value }
    if ($Value = AI_GetMsiProperty DOCS_DBUSER) { AI_SetMsiProperty PS_DB_USER $Value }
    if ($Value = AI_GetMsiProperty DOCS_JWTENABLED) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_ENABLED $Value
        AI_SetMsiProperty JWT_ENABLED $Value
    }
    if ($Value = AI_GetMsiProperty DOCS_JWTHEADER) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_HEADER $Value
        AI_SetMsiProperty JWT_HEADER $Value
    }
    if ($Value = (AI_GetMsiProperty DOCS_JWTSECRET).Trim()) {
        AI_SetMsiProperty DOCUMENT_SERVER_JWT_SECRET $Value
        AI_SetMsiProperty JWT_SECRET $Value
    }
    if ($Value = AI_GetMsiProperty DOCS_RABBITMQHOST) { AI_SetMsiProperty AMQP_HOST $Value }
    if ($Value = AI_GetMsiProperty DOCS_RABBITMQPROTO) { AI_SetMsiProperty AMQP_PROTOCOL $Value }
    if ($Value = (AI_GetMsiProperty DOCS_RABBITMQPWD).Trim()) { AI_SetMsiProperty AMQP_PWD $Value }
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

    $MySqlDriver = ""
    $Paths = @(
        "HKLM:\SOFTWARE\ODBC\ODBCINST.INI",
        "HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI"
    )

    foreach ($path in $Paths) {
        if (Test-Path $path) {
            $keys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
            foreach ($k in $keys) {
                $name = $k.PSChildName
                if ($name -like "*MySQL ODBC*" -and $name -notlike "*ANSI*") {
                    $MySqlDriver = $name
                    break
                }
            }
        }
        if ($MySqlDriver) { break }
    }

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

# Creates a user that can reach only the application database, as the Linux packages do; returns $null when the name is not a plain identifier or the creation fails.
function CreateMySqlApplicationUser {
    param ($Cmd, [string]$DbName)
    if ($DbName -notmatch '^[A-Za-z0-9_]+$') {
        Write-Output "The database name '$DbName' is not a plain identifier, the application keeps using the root user."
        return $null
    }
    # Named after the database, so installations sharing a MySQL server never reset each other's password.
    $AppUser = $DbName.Substring(0, [Math]::Min(27, $DbName.Length)) + '_user'
    $AppPassword = 'Aa1_' + (RandomString -Length 24)
    try {
        foreach ($UserHost in 'localhost', '127.0.0.1') {
            $Cmd.CommandText = "CREATE USER IF NOT EXISTS '$AppUser'@'$UserHost' IDENTIFIED BY '$AppPassword'"
            [void]$Cmd.ExecuteNonQuery()
            $Cmd.CommandText = "ALTER USER '$AppUser'@'$UserHost' IDENTIFIED BY '$AppPassword'"
            [void]$Cmd.ExecuteNonQuery()
            $Cmd.CommandText = "GRANT ALL PRIVILEGES ON ``$DbName``.* TO '$AppUser'@'$UserHost'"
            [void]$Cmd.ExecuteNonQuery()
        }
        $Cmd.CommandText = 'FLUSH PRIVILEGES'
        [void]$Cmd.ExecuteNonQuery()
        Write-Output "The application database user '$AppUser' is created."
        return @{ Name = $AppUser; Password = $AppPassword }
    }
    catch {
        Write-Output "Unable to create the application database user, the application keeps using the root user: $($_.Exception.Message)"
        return $null
    }
}

# Configures MySQL settings by updating my.ini and setting the root password.
function MySQLConfigure {
    $MySqlDriver = Get-ChildItem 'HKLM:\SOFTWARE\ODBC\ODBCINST.INI', 'HKLM:\SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -like '*MySQL ODBC*' -and $_.PSChildName -notlike '*ANSI*' } |
        Select-Object -First 1 -ExpandProperty PSChildName
    $DbName      = AI_GetMsiProperty DB_NAME
    $DbPass      = AI_GetMsiProperty DB_PWD

    $InstallDir = (AI_GetMsiProperty "ProgramFiles64Folder") + "/MySQL/MySQL Server 8.4"
    $DataDir    = (AI_GetMsiProperty "ProgramFiles64Folder") + "/MySQL/MySQL Server 8.4/data"

    Write-Output "MySQLConfigure: InstallDir $InstallDir"
    Write-Output "MySQLConfigure: DataDir $DataDir"

    try {
        $Service = Get-Service -Name "MySQL84" -ErrorAction Stop

        if ($Service.Status -eq 'Running') {
            # The first installation replaces the default root password with a random one.
            if (-not (AI_GetMsiProperty OLDPRODUCTS) -and $DbPass -eq 'root') {
                $NewPass = 'Aa1_' + (RandomString -Length 28)  # the prefix satisfies the default MySQL password policy
                $Conn = New-Object System.Data.Odbc.OdbcConnection("DRIVER={$MySqlDriver};SERVER=127.0.0.1;PORT=$(AI_GetMsiProperty DB_PORT);USER=root;PWD=root;")
                try {
                    $Conn.Open()
                    $Cmd = $Conn.CreateCommand()
                    $Cmd.CommandText = "ALTER USER 'root'@'localhost' IDENTIFIED BY '$NewPass'"
                    [void]$Cmd.ExecuteNonQuery()
                    $AppUser = CreateMySqlApplicationUser $Cmd $DbName
                } finally {
                    $Conn.Close()
                }
                # The administrative password is kept only in the restricted settings key; the application gets its own user.
                AI_SetMsiProperty MYSQL_ROOT_PWD $NewPass
                if ($AppUser) {
                    AI_SetMsiProperty DB_USER $AppUser.Name
                    AI_SetMsiProperty DB_PWD $AppUser.Password
                    SaveSecretsNow @{ MYSQL_ROOT_PWD = $NewPass; DB_USER = $AppUser.Name; DB_PWD = $AppUser.Password }
                } else {
                    AI_SetMsiProperty DB_PWD $NewPass
                    SaveSecretsNow @{ MYSQL_ROOT_PWD = $NewPass; DB_PWD = $NewPass }
                }
            }
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

# Configures PostgreSQL by creating the database and user if they do not exist.
function PostgreSqlConfigure {
    $DbUser = AI_GetMsiProperty PS_DB_USER
    $DbPwd  = AI_GetMsiProperty PS_DB_PWD
    $DbName = AI_GetMsiProperty PS_DB_NAME
    $DbPort = AI_GetMsiProperty PS_DB_PORT
    $DbHost = AI_GetMsiProperty PS_DB_HOST

    # The wizard runs this twice; the second run connects with the superuser password the first one set.
    $SuperPassword = (AI_GetMsiProperty PS_SUPER_PWD).Trim()
    $ConnSuperPassword = if ($SuperPassword) { $SuperPassword } else { 'postgres' }
    $Driver      = "PostgreSQL Unicode"
    $ConnString  = "Driver={$Driver};Server=$DbHost;Port=$DbPort;Database=postgres;Uid=postgres;Pwd=$ConnSuperPassword"

    try {
        $Conn = New-Object System.Data.Odbc.OdbcConnection($ConnString)
        $Conn.Open()
        $Cmd = $Conn.CreateCommand()

        # A fresh install replaces the default application password, unless a silent install already set Docs up with it.
        $DocsInstalled = [bool]((AI_GetMsiProperty DOCS_INSTALLED_VERSION).Trim())
        $Replace = -not (AI_GetMsiProperty OLDPRODUCTS) -and $DbPwd -eq 'onlyoffice' -and -not $DocsInstalled
        if ($Replace) { $DbPwd = RandomString -Length 32 }

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
        } else {
            Write-Output "User '$DbUser' already exists."
            if ($Replace) {
                $Cmd.CommandText = "ALTER USER $DbUser WITH ENCRYPTED PASSWORD '$DbPwd';"
                $Cmd.ExecuteNonQuery()
            }
        }

        if ($Replace) {
            AI_SetMsiProperty PS_DB_PWD $DbPwd
            SaveSecretsNow @{ PS_DB_PWD = $DbPwd }
        }

        $Cmd.CommandText = "GRANT ALL PRIVILEGES ON DATABASE $DbName TO $DbUser;"
        $Cmd.ExecuteNonQuery()
        Write-Output "Granted privileges on database '$DbName' to user '$DbUser'."
        # A database created here belongs to the application user, which needs to create tables in it on PostgreSQL 15 and later.
        if (-not $DbExists) {
            $Cmd.CommandText = "ALTER DATABASE $DbName OWNER TO $DbUser;"
            [void]$Cmd.ExecuteNonQuery()
        }

        if (-not (AI_GetMsiProperty OLDPRODUCTS) -and $DocsInstalled) {
            InitializeDocsSchema $DbHost $DbPort $DbName $DbUser $DbPwd
        }

        # A fresh install replaces the well-known superuser password set by the prerequisites; the new one is kept only in the restricted settings key.
        if (-not (AI_GetMsiProperty OLDPRODUCTS) -and -not $SuperPassword) {
            $SuperPassword = RandomString -Length 32
            $Cmd.CommandText = "ALTER USER postgres WITH ENCRYPTED PASSWORD '$SuperPassword';"
            [void]$Cmd.ExecuteNonQuery()
            AI_SetMsiProperty PS_SUPER_PWD $SuperPassword
            SaveSecretsNow @{ PS_SUPER_PWD = $SuperPassword }
            Write-Output 'The PostgreSQL superuser password is replaced with a random one.'
        }
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

# A fresh install with the local broker gives Apps and Docs their own RabbitMQ user instead of guest.
function RabbitMqConfigure {
    if ((AI_GetMsiProperty OLDPRODUCTS) -or (AI_GetMsiProperty AMQP_USER) -ne 'guest' -or (AI_GetMsiProperty AMQP_HOST) -notin 'localhost', '127.0.0.1') {
        return
    }
    $Ctl = Get-ChildItem "$env:ProgramFiles\RabbitMQ Server\rabbitmq_server-*\sbin\rabbitmqctl.bat" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
    $Cookie = "$env:SystemRoot\System32\config\systemprofile\.erlang.cookie"
    if (-not $Ctl -or -not (Test-Path -LiteralPath $Cookie)) {
        Write-Output 'rabbitmqctl or the broker cookie is not found, Apps keeps using the guest user.'
        return
    }

    # The installing user has its own broker cookie, which the service does not accept, so rabbitmqctl runs with a private home holding the service one.
    # The cookie gives full control of the broker running as LocalSystem, so its folder is closed to other programs of the installing user.
    try { $CtlHome = NewRestrictedTempDir 'rabbitmqctl-' }
    catch {
        Write-Output "Unable to create a restricted folder for the broker cookie, Apps keeps using the guest user: $($_.Exception.Message)"
        return
    }
    try {
        Copy-Item -LiteralPath $Cookie -Destination (Join-Path $CtlHome '.erlang.cookie')
        $User = 'onlyoffice'
        $Password = RandomString -Length 32
        $VHost = AI_GetMsiProperty AMQP_VHOST
        if (-not $VHost) { $VHost = '/' }
        # The prerequisites may have started the broker moments ago, so it gets up to three minutes to come up.
        $Deadline = (Get-Date).AddMinutes(3)
        do {
            $Result = InvokeRabbitMqCtl $Ctl $CtlHome 'await_startup --timeout 60' ''
            if ($Result.ExitCode -eq 0) { break }
            Start-Sleep -Seconds 5
        } while ((Get-Date) -lt $Deadline)
        if ($Result.ExitCode -ne 0) { throw "await_startup failed: $($Result.Output)" }
        [void](InvokeRabbitMqCtl $Ctl $CtlHome "delete_user $User" '')
        # The password goes through stdin, so it never appears in a command line.
        $Result = InvokeRabbitMqCtl $Ctl $CtlHome "add_user $User" $Password
        if ($Result.ExitCode -ne 0) { throw "add_user failed: $($Result.Output)" }
        $Result = InvokeRabbitMqCtl $Ctl $CtlHome "set_permissions -p `"$VHost`" $User `".*`" `".*`" `".*`"" ''
        if ($Result.ExitCode -ne 0) { throw "set_permissions failed: $($Result.Output)" }

        AI_SetMsiProperty AMQP_USER $User
        AI_SetMsiProperty AMQP_PWD $Password
        Write-Output "The RabbitMQ user '$User' is created."
        ShareRabbitMqUserWithDocs $User $Password
    }
    catch {
        Write-Output "Unable to create the RabbitMQ user, Apps keeps using the guest user: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $CtlHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# A silent install runs Docs before the MSI creates the RabbitMQ user, so Docs installed with guest is switched to it here.
function ShareRabbitMqUserWithDocs {
    param ([string]$User, [string]$Password)
    $Base = $null
    $DocsKey = $null
    # The Apps user already exists here, so no failure of this step may reach the catch of RabbitMqConfigure.
    try {
        $DocsDir = GetDocumentServerInstallLocation
        if (-not $DocsDir) { return }
        $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
        $DocsKey = $Base.OpenSubKey('SOFTWARE\ONLYOFFICE\DocumentServer', $true)
        if (-not $DocsKey -or $DocsKey.GetValue('RabbitMqUser') -ne 'guest') { return }
        $DocsKey.SetValue('RabbitMqUser', $User, [Microsoft.Win32.RegistryValueKind]::String)
        $DocsKey.SetValue('RabbitMqPwd', $Password, [Microsoft.Win32.RegistryValueKind]::String)

        # Docs EE/DE keeps the broker URL in local.json (CE has no broker settings); only the credentials of that URL change.
        $LocalJson = Join-Path $DocsDir 'config\local.json'
        if (Test-Path -LiteralPath $LocalJson -PathType Leaf) {
            $Content = [IO.File]::ReadAllText($LocalJson)
            $Credentials = [uri]::EscapeDataString($User) + ':' + [uri]::EscapeDataString($Password)
            $UrlPattern = '("rabbitmq"\s*:\s*\{[^{}]*?"url"\s*:\s*"[A-Za-z][A-Za-z0-9+.-]*://)guest:guest(@[^"]*")'
            $Updated = [regex]::Replace($Content, $UrlPattern, { param($Match) $Match.Groups[1].Value + $Credentials + $Match.Groups[2].Value })
            if ($Updated -cne $Content) {
                [IO.File]::WriteAllText($LocalJson, $Updated, (New-Object Text.UTF8Encoding($false)))
                foreach ($Service in 'DsDocServiceSvc', 'DsConverterSvc') {
                    if (Get-Service -Name $Service -ErrorAction SilentlyContinue) { Restart-Service -Name $Service -Force -ErrorAction SilentlyContinue }
                }
            }
        }
        Write-Output "Docs uses the RabbitMQ user '$User'."
    }
    catch { Write-Output "Unable to give Docs the RabbitMQ user, Docs keeps using guest: $($_.Exception.Message)" }
    finally {
        if ($DocsKey) { $DocsKey.Close() }
        if ($Base) { $Base.Close() }
    }
}

# Console tools such as rabbitmqctl read stdin when it is not a terminal, so stdin is always given and closed; a run that hangs is stopped after two minutes.
function InvokeHiddenProcess {
    param ([string]$FileName, [string]$Arguments, [hashtable]$Environment, [string]$StdinText)
    $Info = New-Object System.Diagnostics.ProcessStartInfo
    $Info.FileName = $FileName
    $Info.Arguments = $Arguments
    $Info.UseShellExecute = $false
    $Info.CreateNoWindow = $true
    $Info.RedirectStandardInput = $true
    $Info.RedirectStandardOutput = $true
    $Info.RedirectStandardError = $true
    foreach ($Name in $Environment.Keys) { $Info.EnvironmentVariables[$Name] = $Environment[$Name] }
    $Process = [System.Diagnostics.Process]::Start($Info)
    $Stdout = $Process.StandardOutput.ReadToEndAsync()
    $Stderr = $Process.StandardError.ReadToEndAsync()
    if ($StdinText) { $Process.StandardInput.WriteLine($StdinText) }
    $Process.StandardInput.Close()
    if (-not $Process.WaitForExit(120000)) {
        $Process.Kill()
        return @{ ExitCode = -1; Output = "$(Split-Path -Leaf $FileName) $($Arguments.Split(' ')[0]) did not finish in time" }
    }
    return @{ ExitCode = $Process.ExitCode; Output = ($Stdout.Result + $Stderr.Result).Trim() }
}

function InvokeRabbitMqCtl {
    param ([string]$Ctl, [string]$CtlHome, [string]$Arguments, [string]$StdinText)
    $Environment = @{ HOMEDRIVE = Split-Path -Qualifier $CtlHome; HOMEPATH = Split-Path -NoQualifier $CtlHome; USERPROFILE = $CtlHome }
    # The prerequisites set ERLANG_HOME for the machine, so a setup started before them does not have it in its environment.
    if (-not $env:ERLANG_HOME) {
        $ErlangHome = [Environment]::GetEnvironmentVariable('ERLANG_HOME', 'Machine')
        if ($ErlangHome) { $Environment['ERLANG_HOME'] = $ErlangHome }
    }
    return InvokeHiddenProcess "$env:SystemRoot\System32\cmd.exe" "/c `"`"$Ctl`" $Arguments`"" $Environment $StdinText
}

# Docs EE/DE installed before its database role existed has no tables, so they are created here and Docs is restarted (CE keeps no data there).
function InitializeDocsSchema {
    param ([string]$DbHost, [string]$DbPort, [string]$DbName, [string]$DbUser, [string]$DbPwd)
    if ((AI_GetMsiProperty ENVIRONMENT) -eq 'community') { return }
    $DocsDir = AI_GetMsiProperty DOCS_INSTALL_LOCATION
    if (-not $DocsDir) { return }
    $Schema = Join-Path $DocsDir 'server\schema\postgresql\createdb.sql'
    $Psql = @(Join-Path $DocsDir 'pgsql\bin\psql.exe') + @(Get-ChildItem "$env:ProgramFiles\PostgreSQL\*\bin\psql.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $Psql -or -not (Test-Path -LiteralPath $Schema)) {
        Write-Output 'psql or the Docs schema is not found, the Docs tables are not checked.'
        return
    }

    # The password reaches psql through its environment, never through the command line.
    $Environment = @{ PGPASSWORD = $DbPwd }
    $Connection = "-h `"$DbHost`" -p `"$DbPort`" -U `"$DbUser`" -d `"$DbName`" -w -q"
    $Check = "$Connection -t -A -c `"SELECT to_regclass('public.task_result') IS NOT NULL;`""
    $Result = InvokeHiddenProcess $Psql $Check $Environment ''
    if ($Result.ExitCode -ne 0) { Write-Output "Unable to check the Docs tables: $($Result.Output)"; return }
    if ($Result.Output -eq 't') { return }

    [void](InvokeHiddenProcess $Psql "$Connection -f `"$Schema`"" $Environment '')
    $Result = InvokeHiddenProcess $Psql $Check $Environment ''
    if ($Result.Output -ne 't') { Write-Output "Unable to create the Docs tables: $($Result.Output)"; return }
    Write-Output 'The Docs tables are created.'
    foreach ($Service in 'DsDocServiceSvc', 'DsConverterSvc') {
        Restart-Service -Name $Service -Force -ErrorAction SilentlyContinue
    }
}

$DocsParamsDirPrefix = 'onlyoffice-apps-docs-params-'

# Hands Docs its secrets in a file; UI sequence only, as a silent install runs Docs before the MSI and Docs then reads the Apps key or generates them.
function WriteDocsParamsFile {
    $Params = [ordered]@{
        JWT_SECRET = AI_GetMsiProperty DOCUMENT_SERVER_JWT_SECRET
        DB_PWD     = AI_GetMsiProperty PS_DB_PWD
    }
    # A RabbitMQ user created for Apps is shared with Docs, which otherwise keeps using guest.
    if ((AI_GetMsiProperty AMQP_USER) -ne 'guest') {
        $Params['RABBITMQ_USER'] = AI_GetMsiProperty AMQP_USER
        $Params['RABBITMQ_PWD'] = AI_GetMsiProperty AMQP_PWD
    }

    RemoveDocsParamsFile
    # No other user can prepare, replace or read the folder.
    try { $Dir = NewRestrictedTempDir $DocsParamsDirPrefix }
    catch {
        # Without the restricted folder no file is written, and Docs takes its secrets as on a silent install.
        Write-Output "WARNING: the Docs parameters folder cannot be restricted, so no parameters file is written: $($_.Exception.Message)"
        return
    }

    $File = Join-Path $Dir 'docs-params.ini'
    $Lines = $Params.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    [IO.File]::WriteAllLines($File, [string[]]$Lines, (New-Object Text.UTF8Encoding($false)))
    AI_SetMsiProperty DOCS_PARAMS_FILE $File
    Write-Output 'The Docs secrets are passed in a parameters file.'
}

# Docs deletes the parameters file after reading it; this removes its folder, the file when Docs did not run, and folders left by an interrupted setup.
function RemoveDocsParamsFile {
    $Dirs = @(Get-ChildItem -LiteralPath $env:TEMP -Directory -Force -Filter "$DocsParamsDirPrefix*" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    $File = (AI_GetMsiProperty DOCS_PARAMS_FILE).Trim()
    if ($File) { $Dirs += Split-Path -Parent $File }
    foreach ($Dir in $Dirs | Select-Object -Unique) {
        if ((Split-Path -Leaf $Dir) -notlike "$DocsParamsDirPrefix*") { continue }
        $Item = Get-Item -LiteralPath $Dir -Force -ErrorAction SilentlyContinue
        if (-not $Item -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        # Only a folder owned by SYSTEM or Administrators is removed: other users cannot create, rename or replace one, so the checks cannot be raced.
        $Owner = (Get-Acl -LiteralPath $Dir).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
        if ($Owner -notin 'S-1-5-18', 'S-1-5-32-544') { continue }
        Remove-Item -LiteralPath $Dir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Sets a random JWT secret property for the document server.
function SetDocumentServerJWTSecretProp {
    $JwtSecret = RandomString -Length 30
    AI_SetMsiProperty JWT_SECRET $JwtSecret
}

# Sets the MACHINE_KEY MSI property from the installed configuration, or a random one when there is none.
function SetMachineKey {
    $AppDir = AI_GetMsiProperty APPDIR
    $MachineKey = ""

    # The key is in appsettings.<ENVIRONMENT>.json of the installed edition, which differs on an edition change; a new key would break the data protected with the old one
    $JsonNames = @("appsettings.$(AI_GetMsiProperty ENVIRONMENT).json", 'appsettings.community.json', 'appsettings.enterprise.json', 'appsettings.developer.json', 'appsettings.production.json') | Select-Object -Unique
    # When files of several editions are left, the most recently written one holds the key in use
    $JsonFiles = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    foreach ($JsonName in $JsonNames) {
        $JsonFilePath = Join-Path -Path $AppDir -ChildPath "config\$JsonName"
        try { if (Test-Path -LiteralPath $JsonFilePath -PathType Leaf) { $JsonFiles.Add((Get-Item -LiteralPath $JsonFilePath -ErrorAction Stop)) } }
        catch { Write-Output "Unable to read $JsonFilePath : $($_.Exception.Message)" }
    }
    $JsonFiles = $JsonFiles | Sort-Object LastWriteTimeUtc -Descending
    foreach ($JsonFile in $JsonFiles) {
        try {
            $MachineKey = (Get-Content -LiteralPath $JsonFile.FullName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).core.machinekey
            if (-not [string]::IsNullOrEmpty($MachineKey)) { break }
        }
        catch { Write-Output "Unable to read $($JsonFile.FullName) : $($_.Exception.Message)" }
    }

    if ($MachineKey -and -not $MachineKey.Trim()) {
        Write-Output "WARNING: the installed MACHINE_KEY is blank; it is kept because a new key would make the stored passwords and data unreadable."
    }

    if ([string]::IsNullOrEmpty($MachineKey)) {
        $MachineKey = RandomString -Length 32
        Write-Output "MACHINE_KEY is set to a random string."
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

# Sets IDENTITY_ENCRYPTION_SECRET when the registry has no value: a new one on a fresh install, the installed one on an update.
function SetIdentityEncryptionSecret {
    AI_SetMsiProperty IDENTITY_SECRET_MISSING ''
    if (-not (AI_GetMsiProperty OLDPRODUCTS)) {
        AI_SetMsiProperty IDENTITY_ENCRYPTION_SECRET (RandomString -Length 32)
        return
    }

    # A new key would make the Identity data unreadable, so an update takes the key from the installed service configuration.
    $ServiceConfig = Join-Path (AI_GetMsiProperty APPDIR) 'tools\Identity.Authorization.xml'
    try {
        if (Test-Path -LiteralPath $ServiceConfig -PathType Leaf) {
            $Secret = ([xml](Get-Content -LiteralPath $ServiceConfig -Raw)).service.env |
                Where-Object { $_.name -eq 'SPRING_APPLICATION_ENCRYPTION_SECRET' } | Select-Object -First 1 -ExpandProperty value
            # A silent install of 4.0 and older left the blank placeholder here, and its Identity data is encrypted with it
            if ($Secret -and $Secret -ne '{IDENTITY_ENCRYPTION_SECRET}') {
                if (-not $Secret.Trim()) { Write-Output 'WARNING: the installed Identity encryption key is blank; it is kept so that the Identity data stays readable.' }
                AI_SetMsiProperty IDENTITY_ENCRYPTION_SECRET $Secret
                Write-Output 'IDENTITY_ENCRYPTION_SECRET is taken from the installed Identity service configuration.'
                return
            }
        }
    }
    catch { Write-Output "Unable to read $ServiceConfig : $($_.Exception.Message)" }

    Write-Output 'ERROR: the Identity encryption key of the installed version was not found; the update stops so that the Identity data stays readable.'
    AI_SetMsiProperty IDENTITY_SECRET_MISSING '1'
}

# Function to set up OpenSearch.
function OpenSearchSetup {
    $AppDir = AI_GetMsiProperty APPDIR
    $AppIndexDir = Join-Path $AppDir "Data\Index\v3.5.0\"
    $LogsDir     = Join-Path $AppDir "Logs\"
    # OpenSearchStack unpacks Dashboards into opensearch-dashboards-<version>, so the folder is found by pattern and the newest version wins
    $OpenSearchDashboardsDir = GetNewestVersionedFolder "C:\OpenSearchStack" "opensearch-dashboards-*"

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
    $OpenSearchDashboardsYml = if ($OpenSearchDashboardsDir) { Join-Path $OpenSearchDashboardsDir.FullName "config\opensearch_dashboards.yml" }
    if (-not $OpenSearchDashboardsYml -or -not (Test-Path $OpenSearchDashboardsYml)) {
        Write-Output "OpenSearch Dashboards configuration not found in C:\OpenSearchStack\opensearch-dashboards-*\config, Dashboards is not configured."
        return
    }
    Set-Content -Path $OpenSearchDashboardsYml -Value "" -Force

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

# A silent install runs Docs before APPDIR is known, so Docs and then Apps get the C:\APPDIR placeholder as the license path; both are pointed at Apps\Data.
function RepairDocsLicensePath {
    $Placeholder = '^C:[\\/]+APPDIR[\\/]'
    $LicensePath = (AI_GetMsiProperty LICENSE_PATH).Trim()
    if (-not $LicensePath -or $LicensePath -match $Placeholder -or $LicensePath -notmatch '^([A-Za-z]:[\\/]|\\\\)') {
        $DefaultPath = Join-Path (AI_GetMsiProperty APPDIR) 'Data\license.lic'
        # A license saved under the placeholder by an earlier silent install moves with the path.
        $OldLicense = $LicensePath -replace '/', '\'
        if ($LicensePath -match $Placeholder -and (Test-Path -LiteralPath $OldLicense -PathType Leaf) -and -not (Test-Path -LiteralPath $DefaultPath)) {
            try {
                New-Item -ItemType Directory -Path (Split-Path -Parent $DefaultPath) -Force -ErrorAction Stop | Out-Null
                Copy-Item -LiteralPath $OldLicense -Destination $DefaultPath -ErrorAction Stop
            }
            catch { Write-Warning "Unable to copy the license from $OldLicense to ${DefaultPath}: $($_.Exception.Message)" }
        }
        $LicensePath = $DefaultPath
        AI_SetMsiProperty LICENSE_PATH $LicensePath
        Write-Output "License path set to $LicensePath."
    }

    # The repair is best effort: a failure is logged and the installation goes on.
    try {
        $DocsDir = AI_GetMsiProperty DOCS_INSTALL_LOCATION
        $RegistryDocsDir = GetDocumentServerInstallLocation
        if ($RegistryDocsDir) { $DocsDir = $RegistryDocsDir }
        if (-not $DocsDir) { return }
        $DocsConfig = Join-Path $DocsDir 'config\local.json'
        if (-not (Test-Path -LiteralPath $DocsConfig -PathType Leaf)) { return }

        # The value is replaced in the text, so the rest of the Docs config keeps its formatting.
        $Pattern = '("license_file"\s*:\s*")C:[\\/]+APPDIR[\\/][^"]*(")'
        $Text = [IO.File]::ReadAllText($DocsConfig)
        if ($Text -notmatch $Pattern) { return }
        $DocsLicensePath = $LicensePath -replace '\\', '/'
        $Text = [regex]::Replace($Text, $Pattern, { param($Match) $Match.Groups[1].Value + $DocsLicensePath + $Match.Groups[2].Value }, 'IgnoreCase')
        [IO.File]::WriteAllText($DocsConfig, $Text, (New-Object Text.UTF8Encoding($false)))
    }
    catch {
        Write-Warning "Unable to update the license path in the Docs configuration: $($_.Exception.Message)"
        return
    }
    foreach ($Service in 'DsDocServiceSvc', 'DsConverterSvc') {
        Restart-Service -Name $Service -Force -ErrorAction SilentlyContinue
    }
    Write-Output "Docs license path set to $DocsLicensePath."
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

# Only SYSTEM and Administrators can read the passwords and keys stored in a product registry key; the 32-bit view is where this package writes them.
function LockRegistryKey {
    param ([string]$SubKey)
    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
    try {
        $Key = $Base.CreateSubKey($SubKey)
        try {
            $Security = New-Object System.Security.AccessControl.RegistrySecurity
            $Security.SetSecurityDescriptorSddlForm('D:PAI(A;CI;KA;;;SY)(A;CI;KA;;;BA)')
            $Key.SetAccessControl($Security)
        } finally { $Key.Close() }
    } finally { $Base.Close() }
}

# The settings key of this product under HKLM, where the package writes its passwords and keys.
function GetProductRegistryKey {
    return 'Software\' + (AI_GetMsiProperty Manufacturer) + '\' + (AI_GetMsiProperty ShortProductName)
}

# A password replaced before the installation starts is saved at once, so a cancelled or rolled back setup can still read it on the next run.
function SaveSecretsNow {
    param ([hashtable]$Values)
    try {
        $SubKey = GetProductRegistryKey
        LockRegistryKey $SubKey
        $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
        try {
            $Key = $Base.CreateSubKey($SubKey)
            try { foreach ($Name in $Values.Keys) { $Key.SetValue($Name, [string]$Values[$Name], 'String') } } finally { $Key.Close() }
        } finally { $Base.Close() }
    }
    catch {
        Write-Output "WARNING: the new passwords are not saved before the installation, so a cancelled setup loses them: $($_.Exception.Message)"
    }
}

# Creates a new random folder in TEMP owned by Administrators that only SYSTEM and Administrators can open; it gets this ACL as it is created.
function NewRestrictedTempDir {
    param ([string]$Prefix)
    $Security = New-Object System.Security.AccessControl.DirectorySecurity
    $Security.SetSecurityDescriptorSddlForm('O:BAD:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
    $Dir = Join-Path $env:TEMP ($Prefix + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($Dir, $Security)
    return $Dir
}

# The services run as LocalService: they read the install directory and write only Data, Logs and the backup temp folders.
function LockInstallDir {
    param ([string]$AppDir)
    $ReadOnlySddl = 'D:PAI(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;0x1200a9;;;LS)'
    $Existed = Test-Path -LiteralPath $AppDir
    New-Item -ItemType Directory -Force -Path $AppDir | Out-Null
    $Security = Get-Acl -LiteralPath $AppDir
    $Sids = $Security.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value }
    $AlreadyLocked = $Security.AreAccessRulesProtected -and ($Sids -contains 'S-1-5-19') -and -not ($Sids | Where-Object { $_ -notin 'S-1-5-18', 'S-1-5-32-544', 'S-1-5-19' })
    if (-not $AlreadyLocked) {
        $Security = New-Object System.Security.AccessControl.DirectorySecurity
        $Security.SetSecurityDescriptorSddlForm($ReadOnlySddl)
        Set-Acl -LiteralPath $AppDir -AclObject $Security
    }
    # The first upgrade from an older version resets explicit entries on the children (Data excluded, it only inherits) to the new parent ACL.
    if ($Existed -and -not $AlreadyLocked) {
        Get-ChildItem -LiteralPath $AppDir -Force | Where-Object { $_.Name -ne 'Data' } | ForEach-Object {
            & "$env:SystemRoot\System32\icacls.exe" $_.FullName /reset /T /C /Q | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "icacls /reset failed for $($_.FullName) with exit code $LASTEXITCODE" }
        }
    }
    GrantWritableDirs $AppDir
}

# Repeats the grants after the files are installed; it runs after InstallFinalize, so a failure is only logged.
function GrantWritableDirsAfterInstall {
    try {
        GrantWritableDirs (AI_GetMsiProperty APPDIR)
        Write-Output 'The writable folders are granted to LocalService.'
    }
    catch { Write-Output "WARNING: could not grant the writable folders to LocalService: $($_.Exception.Message)" }
}

# LocalService writes Data, Logs and the backup temp folders; the folders are created when missing, because the old version removes empty ones on an upgrade.
function GrantWritableDirs {
    param ([string]$AppDir)
    if (-not $AppDir) { $AppDir = AI_GetMsiProperty APPDIR }
    $WritableDirs = 'Data', 'Logs', 'services\ASC.Data.Backup\service\temp', 'services\ASC.Data.Backup.Worker\service\temp'
    foreach ($RelativeDir in $WritableDirs) {
        $Dir = Join-Path $AppDir $RelativeDir
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        # A grant that is already there is skipped, so an upgrade does not walk a large Data tree again.
        $Granted = (Get-Acl -LiteralPath $Dir).GetAccessRules($true, $false, [System.Security.Principal.SecurityIdentifier]) | Where-Object {
            $_.IdentityReference.Value -eq 'S-1-5-19' -and $_.AccessControlType -eq 'Allow' -and
            ($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) -eq [System.Security.AccessControl.FileSystemRights]::Modify -and
            $_.InheritanceFlags -eq 'ContainerInherit, ObjectInherit' }
        if ($Granted) { continue }
        & "$env:SystemRoot\System32\icacls.exe" $Dir /grant '*S-1-5-19:(OI)(CI)M' /C /Q | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "icacls /grant failed for $Dir with exit code $LASTEXITCODE" }
    }
}

# Locks the settings key and the install directory before any secret is written into them; on an upgrade this runs before the previous version is removed.
function LockSecrets {
    AI_SetMsiProperty SECRETS_LOCK_FAILED ''
    try {
        LockRegistryKey (GetProductRegistryKey)
        # A legacy key left behind by a failed rename still holds the old secrets.
        $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
        try { $LegacyExists = $null -ne $Base.OpenSubKey('Software\Ascensio System SIA\ONLYOFFICE DocSpace') } finally { $Base.Close() }
        if ($LegacyExists) { LockRegistryKey 'Software\Ascensio System SIA\ONLYOFFICE DocSpace' }
        LockInstallDir (AI_GetMsiProperty APPDIR)
        Write-Output 'The settings key and the install directory are restricted.'
    }
    catch {
        Write-Output "ERROR: could not restrict access to the settings key or the install directory: $($_.Exception.Message)"
        AI_SetMsiProperty SECRETS_LOCK_FAILED '1'
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
    # OpenSearchStack unpacks Fluent Bit into fluent-bit-<version>, so the folder is found by pattern and the newest version wins
    $FluentBitDir = GetNewestVersionedFolder "C:\OpenSearchStack" "fluent-bit-*"

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
        Invoke-Expression $PsCommand
    } else {
        Write-Output "SSL script not executed. Missing paths or ConfigSslFile."
    }

    # Manage Fluent Bit configuration.
    if ($FluentBitDir) {
        $FluentBitDstFolder = Join-Path $FluentBitDir.FullName "conf\"
        $FluentBitConfPath = Join-Path $FluentBitDstFolder "fluent-bit.conf"
        if (Test-Path $FluentBitConfPath) {
            Remove-Item -Path $FluentBitConfPath -Force
        }
        if (Test-Path $FluentBitSourceFile) {
            Move-Item -Path $FluentBitSourceFile -Destination $FluentBitDstFolder
        }
    } else {
        Write-Output "Fluent Bit folder not found in C:\OpenSearchStack\fluent-bit-*, its configuration is not updated."
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

    SetIdentityJavaPath
    ResetPrerequisiteServicePriority
    Write-Output "Script execution completed."
}

# Returns java.exe of the newest JDK 17 or later registered by its installer (Identity needs Java 17), or nothing.
function GetJdkJavaPath {
    $Base = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry64')
    $JdkKey = $null
    try {
        $JdkKey = $Base.OpenSubKey('SOFTWARE\JavaSoft\JDK')
        if (-not $JdkKey) { return }
        $Candidates = foreach ($VersionName in $JdkKey.GetSubKeyNames()) {
            # A JDK registers both its major version and its full version, such as 25 and 25.0.3.
            $Version = $null
            if (-not [version]::TryParse(($VersionName -replace '^(\d+)$', '$1.0'), [ref]$Version) -or $Version.Major -lt 17) { continue }
            $VersionKey = $JdkKey.OpenSubKey($VersionName)
            if (-not $VersionKey) { continue }
            $JavaHome = "$($VersionKey.GetValue('JavaHome'))"
            $VersionKey.Close()
            if (-not $JavaHome) { continue }
            $JavaExe = Join-Path $JavaHome 'bin\java.exe'
            if (Test-Path -LiteralPath $JavaExe -PathType Leaf) { [pscustomobject]@{ Version = $Version; Path = $JavaExe } }
        }
        ($Candidates | Sort-Object Version -Descending | Select-Object -First 1).Path
    }
    finally { if ($JdkKey) { $JdkKey.Close() }; $Base.Close() }
}

# WinSW runs Identity with the first java on the PATH of the service, which may be an older Java, so the JDK path is written into its configs.
function SetIdentityJavaPath {
    $JavaExe = GetJdkJavaPath
    if (-not $JavaExe) {
        Write-Output "No JDK 17 or later is registered, Identity keeps starting java from PATH."
        return
    }
    $AppDir = AI_GetMsiProperty APPDIR
    $Replacement = '<executable>' + [Security.SecurityElement]::Escape($JavaExe) + '</executable>'
    foreach ($Name in 'Identity.Authorization', 'Identity.Registration') {
        try {
            $Config = Join-Path $AppDir "tools\$Name.xml"
            if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { continue }
            $Content = [IO.File]::ReadAllText($Config)
            # Only the bare command shipped in the package is replaced, so a path set by an administrator stays.
            $Updated = [regex]::Replace($Content, '<executable>\s*java(?:\.exe)?\s*</executable>', { param($Match) $Replacement }, 'IgnoreCase')
            if ($Updated -ceq $Content) { continue }
            [IO.File]::WriteAllText($Config, $Updated, (New-Object Text.UTF8Encoding($false)))
            # WinSW reads the executable when the service starts; a failed start may have left the service stopped.
            $ServiceName = AI_GetMsiProperty "ServiceName_$Name"
            $Service = if ($ServiceName) { Get-Service -Name $ServiceName -ErrorAction SilentlyContinue }
            if (-not $Service) {
                Write-Output "$Name is set to run $JavaExe, but its service '$ServiceName' is not found to restart."
                continue
            }
            if ($Service.Status -eq 'Running') { Restart-Service -Name $ServiceName -Force -ErrorAction Stop }
            else { Start-Service -Name $ServiceName -ErrorAction Stop }
            Write-Output "$Name runs $JavaExe."
        }
        catch { Write-Output "Unable to set the Java path of ${Name}: $($_.Exception.Message)" }
    }
}

# Apps 4.0 ran OpenResty and OpenSearch with RealTime priority; an update keeps their installers of the same version, so their WinSW configs are reset here.
function ResetPrerequisiteServicePriority {
    foreach ($Name in 'OpenResty', 'OpenSearch', 'OpenSearchDashboards') {
        try {
            $Service = Get-CimInstance Win32_Service -Filter "Name='$Name'" -ErrorAction Stop
            if (-not $Service) { continue }
            # WinSW reads the XML next to its executable, with the same base name.
            $Executable = if ($Service.PathName -match '^\s*"([^"]+)"') { $Matches[1] } else { ($Service.PathName -split '\s+')[0] }
            $Config = [IO.Path]::ChangeExtension($Executable, '.xml')
            if (-not (Test-Path -LiteralPath $Config -PathType Leaf)) { continue }
            $Content = [IO.File]::ReadAllText($Config)
            $Updated = $Content -replace '<priority>\s*RealTime\s*</priority>', '<priority>Normal</priority>'
            if ($Updated -ceq $Content) { continue }
            [IO.File]::WriteAllText($Config, $Updated, (New-Object Text.UTF8Encoding($false)))
            # WinSW applies the priority when the service starts.
            if ($Service.State -eq 'Running') { Restart-Service -Name $Name -Force -ErrorAction Stop }
            Write-Output "$Name priority is set to Normal."
        }
        catch { Write-Output "Unable to reset the priority of ${Name}: $($_.Exception.Message)" }
    }
}


if (Get-Command -Name $FunctionName -CommandType Function -ErrorAction SilentlyContinue) {
    # Call the function dynamically
    & $FunctionName
} else {
    Write-Error "Function '$FunctionName' is not defined."
}
