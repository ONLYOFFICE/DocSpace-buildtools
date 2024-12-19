Param (
    [string]$FunctionName
)

# Generates a random string of the specified length.
function RandomString {
    param (
        [int]$Length
    )
    $Characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    $RandomString = -join (1..$Length | ForEach-Object {
        $Characters[(Get-Random -Minimum 0 -Maximum $Characters.Length)]
    })
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

# Tests the connection to PostgreSQL using ODBC.
function TestPostgreSqlConnection {
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

    $ConnectionString = "DRIVER={MySQL ODBC 8.0 Unicode Driver};SERVER=$Server;PORT=$Port;USER=$Uid;PASSWORD=$Pwd;"
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

# Configures MySQL settings by updating my.ini and setting the root password.
function MySQLConfigure {
    $MySqlDriver = AI_GetMsiProperty MYSQLODBCDRIVER
    $DbName      = AI_GetMsiProperty DB_NAME
    $DbPass      = AI_GetMsiProperty DB_PWD

    $InstallDir = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\MySQL AB\MySQL Server 8.0" -Name "Location"
    $DataDir    = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\MySQL AB\MySQL Server 8.0" -Name "DataLocation"

    Write-Output "MySQLConfigure: InstallDir $InstallDir"
    Write-Output "MySQLConfigure: DataDir $DataDir"

    try {
        $Service = Get-Service -Name "MySQL80" -ErrorAction Stop

        if ($Service.Status -eq 'Running') {
            $MySqlPath = Join-Path $InstallDir "bin\mysql.exe"
            & $MySqlPath -u root --password=$DbPass -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$DbPass';"
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

    $Driver      = "PostgreSQL Unicode"
    $ConnString  = "Driver={$Driver};Server=$DbHost;Port=$DbPort;Database=postgres;Uid=postgres;Pwd=postgres"

    try {
        $Conn = New-Object System.Data.Odbc.OdbcConnection($ConnString)
        $Conn.Open()
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
        } else {
            Write-Output "User '$DbUser' already exists."
        }

        $Cmd.CommandText = "GRANT ALL PRIVILEGES ON DATABASE $DbName TO $DbUser;"
        $Cmd.ExecuteNonQuery()
        Write-Output "Granted privileges on database '$DbName' to user '$DbUser'."
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
        $MachineKey = RandomString -Length 16
        Write-Output "MACHINE_KEY is set to random string: $MachineKey"
    } else {
        Write-Output "MACHINE_KEY is set to: $MachineKey"
    }

    AI_SetMsiProperty MACHINE_KEY $MachineKey
}

# Sets a random DASHBOARDS_PWD property.
function SetDashboardsPwd {
    $DashboardsPwd = RandomString -Length 20
    AI_SetMsiProperty DASHBOARDS_PWD $DashboardsPwd
}

# Function to set up OpenSearch.
function OpenSearchSetup {
    $AppDir = AI_GetMsiProperty APPDIR
    $AppIndexDir = Join-Path $AppDir "Data\Index\v2.11.1\"
    $LogsDir     = Join-Path $AppDir "Logs\"
    $OpenSearchDashboardsYml = "C:\OpenSearchStack\opensearch-dashboards-2.11.1\config\opensearch_dashboards.yml"

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
    $FileContent = UpdateConfig $FileContent "#path.data:.*" "path.data: $AppIndexDir"
    $FileContent = UpdateConfig $FileContent "#path.logs:.*" "path.logs: $LogsDir"
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

# Function to move configurations and manage files.
function MoveConfigs {
    # Define source and target paths.
    $AppDir = AI_GetMsiProperty APPDIR
    $SourceFolder = Join-Path $AppDir "nginx\conf"
    $TargetFolder = "C:\OpenResty\conf\"
    $NginxFolder = Join-Path $AppDir "nginx"
    $ConfigSslFile = Join-Path $TargetFolder "onlyoffice-proxy-ssl.conf.tmpl"
    $ConfigFile = Join-Path $TargetFolder "onlyoffice-proxy.conf"
    $SslScriptPath = Join-Path $AppDir "sbin\docspace-ssl-setup.ps1"
    $FluentBitSourceFile = Join-Path $AppDir "config\fluent-bit.conf"
    $FluentBitDstFolder = "C:\OpenSearchStack\fluent-bit-2.2.2-win64\conf\"

    # Extract SSL certificate and key paths if config file exists.
    if (Test-Path $ConfigFile) {
        $Content = ReadFileContent $ConfigFile
        $SslCertPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate\s+(.*?);"
        $SslCertKeyPath = ExtractPath -Content $Content -RegexPattern "ssl_certificate_key\s+(.*?);"
    } else {
        Write-Output "Configuration file not found!"
    }

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
    if (Test-Path $ConfigSslFile)  {
        $PsCommand = "& '$SslScriptPath' -f $SslCertPath $SslCertKeyPath"
        Invoke-Expression $PsCommand
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

    Write-Output "Script execution completed."
}


if (Get-Command -Name $FunctionName -CommandType Function -ErrorAction SilentlyContinue) {
    # Call the function dynamically
    & $FunctionName
} else {
    Write-Error "Function '$FunctionName' is not defined."
}
