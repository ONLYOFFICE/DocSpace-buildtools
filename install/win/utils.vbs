Function RedisSetup
    On Error Resume Next
 
    Dim Shell

    Set Shell = CreateObject("WScript.Shell")
        
    Shell.Run "redis-cli config set save """"", 0, True
    Shell.Run "redis-cli config rewrite", 0, True
    
    Set Shell = Nothing
End Function

Function TestPostgreSqlConnection
    On Error Resume Next

    Dim ErrorText
    Dim Pos, postgreSqlDriver

    postgreSqlDriver = "PostgreSQL Unicode(x64)"

    Session.Property("PostgreSqlConnectionError") = ""

    Set ConnectionObject = CreateObject("ADODB.Connection")
    ConnectionObject.Open "Driver={" & postgreSqlDriver & "};" & _
                          "Server=" & Session.Property("PS_DB_HOST") & ";" & _
                          "Port=" & Session.Property("PS_DB_PORT")  & ";" & _
                          "Database=" & Session.Property("PS_DB_NAME") & ";" & _
                          "Uid=" & Session.Property("PS_DB_USER") & ";" & _
                          "Pwd=" & Session.Property("PS_DB_PWD")
    
    If Err.Number <> 0 Then
        ErrorText = Err.Description
        Pos = InStrRev( ErrorText, "]" )
        If 0 < Pos Then
            ErrorText = Right( ErrorText, Len( ErrorText ) - Pos )
        End If
        Session.Property("PostgreSqlConnectionError") = ErrorText
    End If

    ConnectionObject.Close
    
    Set ConnectionObject = Nothing
   
End Function

Function PostgreSqlConfigure
    On Error Resume Next
    
   If (StrComp(Session.Property("POSTGRE_SQL_PATH"),"FALSE") = 0) Then
            Wscript.Quit
    End If

    Dim ErrorText
    Dim Pos, postgreSqlDriver
    Dim databaseUserName
    Dim databaseUserPwd
    Dim databaseName
    Dim databasePort
    Dim databaseHost

    databaseUserName = Session.Property("PS_DB_USER")
    databaseUserPwd = Session.Property("PS_DB_PWD")
    databaseName = Session.Property("PS_DB_NAME")
    databasePort = Session.Property("PS_DB_PORT")
    databaseHost = Session.Property("PS_DB_HOST")

    Call WriteToLog("PostgreSqlConfig: databaseUserName is " & databaseUserName)
    Call WriteToLog("PostgreSqlConfig: databaseUserPwd is " & databaseUserPwd)
    Call WriteToLog("PostgreSqlConfig: databaseName is " & databaseName)
    Call WriteToLog("PostgreSqlConfig: databasePort is " & databasePort)
    Call WriteToLog("PostgreSqlConfig: databaseHost is " & databaseHost)

    postgreSqlDriver = "PostgreSQL Unicode(x64)"

    Set ConnectionObject = CreateObject("ADODB.Connection")
    ConnectionObject.Open "Driver={" & postgreSqlDriver & "};Server=" & databaseHost & ";Port=" & databasePort & ";Database=" & "postgres" & ";Uid=" & "postgres" & ";Pwd=" & "postgres"
            
    ConnectionObject.Execute "CREATE DATABASE " & databaseName
    ConnectionObject.Execute "create user " & databaseUserName & " with encrypted password '" & databaseUserPwd & "'" 
    ConnectionObject.Execute "grant all privileges on database " & databaseName & " to " & databaseUserName
    
    If Err.Number <> 0 Then
        ErrorText = Err.Description
        Pos = InStrRev( ErrorText, "]" )
        If 0 < Pos Then
            Call WriteToLog("PostgreSqlConfig: error is " & ErrorText)
            ErrorText = Right( ErrorText, Len( ErrorText ) - Pos )
            Session.Property("PostgreSqlConnectionError") = ErrorText

        End If
    End If
    
    ConnectionObject.Close
    
    Set ConnectionObject = Nothing

End Function

Function RandomString( ByVal strLen )
    Dim str, min, max

    Const LETTERS = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLOMNOPQRSTUVWXYZ0123456789"
    min = 1
    max = Len(LETTERS)

    Randomize
    For i = 1 to strLen
        str = str & Mid( LETTERS, Int((max-min+1)*Rnd+min), 1 )
    Next
    RandomString = str  
End Function

Function SetDocumentServerJWTSecretProp
    On Error Resume Next

    Session.Property("JWT_SECRET") = RandomString( 30 )

End Function

Function SetMACHINEKEY
    On Error Resume Next

    Dim strFilePath, strJSON, strPattern, objRegExp, objMatches

    ' Specify the path to your JSON file
    strFilePath = Session.Property("APPDIR") & "config\appsettings.production.json"

    ' Read the JSON content
    Set objFSO = CreateObject("Scripting.FileSystemObject")
    Set objFile = objFSO.OpenTextFile(strFilePath, 1)
    strJSON = objFile.ReadAll
    objFile.Close

    ' Define the regular expression pattern to match the "machinekey" value
    strPattern = """machinekey"": ""([^""]+)"""

    ' Create a regular expression object and execute the pattern on the JSON string
    Set objRegExp = New RegExp
    objRegExp.Global = False
    objRegExp.IgnoreCase = True
    objRegExp.Pattern = strPattern

    Set objMatches = objRegExp.Execute(strJSON)

    ' Check if a match was found
    If objMatches.Count > 0 Then
        Session.Property("MACHINE_KEY") = objMatches(0).Submatches(0)
    Else
        Session.Property("MACHINE_KEY") = RandomString(16)
    End If

End Function

Function MySQLConfigure
    On Error Resume Next
    
    Dim installed, service

    Const HKLM = &H80000002
    Set registry = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    registry.EnumKey HKLM, "SOFTWARE\ODBC\ODBCINST.INI", keys
    If Not IsNull(keys) Then
        For Each key In keys
            If InStr(1, key, "MySQL ODBC", 1) <> 0 And InStr(1, key, "ANSI", 1) = 0 Then
                mysqlDriver = key
            End If
        Next
    End If

    If mysqlDriver = "" Then
        registry.EnumKey HKLM, "SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI", keys
        If Not IsNull(keys) Then
            For Each key In keys
                If InStr(1, key, "MySQL ODBC", 1) <> 0 And InStr(1, key, "ANSI", 1) = 0 Then
                    mysqlDriver = key
                End If
            Next
        End If
    End If
    
    Session.Property("MYSQLODBCDRIVER") = mysqlDriver

    Set shell = CreateObject("WScript.Shell")
    dbname = Session.Property("DB_NAME")
    dbpass = Session.Property("DB_PWD")
	
    Err.Clear
    installDir = shell.RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\MySQL AB\MySQL Server 8.0\Location")
    dataDir = shell.RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\MySQL AB\MySQL Server 8.0\DataLocation")

    Call WriteToLog("MySQLConfigure: installDir " & installDir)
    Call WriteToLog("MySQLConfigure: dataDir " & dataDir)

	    
	If Err.Number <> 0 Then
        Err.Clear
        installDir = shell.RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\MySQL AB\MySQL Server 8.0\Location")
 	    dataDir = shell.RegRead("HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\MySQL AB\MySQL Server 8.0\DataLocation") 
    End If

    Call WriteToLog("MySQLConfigure: installDir " & installDir)
    Call WriteToLog("MySQLConfigure: dataDir " & dataDir)
	

    If Err.Number = 0 Then
		Set wmiService = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
        Set service = wmiService.Get("Win32_Service.Name='MySQL80'")

		If Err.Number <> 0 Then
			WScript.Echo "MySQL80 service doesn't exists."
			Wscript.Quit 1
		End If 

		If service.Started Then			
			shell.Run """" & installDir & "bin\mysqladmin"" -u root password " & dbpass, 0, true
            shell.Run """" & installDir & "bin\mysql"" -u root -p" & dbpass & " -e ""ALTER USER 'root'@'localhost' IDENTIFIED BY " & "'" & dbpass & "';""", 0, true	
        End If        
		
        Set filesys = CreateObject("Scripting.FileSystemObject")

		WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "sql-mode", "NO_ENGINE_SUBSTITUTION"
		WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "max_connections", "1000"
		WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "max_allowed_packet", "1048576000"
        WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "group_concat_max_len", "2048"
        WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "character_set_server", "utf8"
        WriteIni filesys.BuildPath(dataDir, "my.ini"), "mysqld", "collation_server", "utf8_general_ci"
		
	    Call WriteToLog("MySQLConfigure: WriteIni Path" & filesys.BuildPath(dataDir, "my.ini"))

    End If
End Function

Function WriteToLog(ByVal var)

    Const MsgType = &H04000000
    Set rec = Installer.CreateRecord(1)

    rec.StringData(1) = CStr(var)
    Session.Message MsgType, rec
    WriteToLog = 0

End Function

Function OpenSearchSetup
    On Error Resume Next
    
    Dim ShellCommand
    Dim APP_INDEX_DIR, OPENSEARCH_DASHBOARDS_YML
    
    Const ForReading = 1
    Const ForWriting = 2
    
    Set Shell = CreateObject("WScript.Shell")
    Set objFSO = CreateObject("Scripting.FileSystemObject")

    APP_INDEX_DIR = Session.Property("APPDIR") & "Data\Index\v2.11.1\"

    OPENSEARCH_DASHBOARDS_YML = "C:\OpenSearchStack\opensearch-dashboards-2.11.1\config\opensearch_dashboards.yml"
   
    If Not fso.FolderExists(APP_INDEX_DIR) Then
        Session.Property("NEED_REINDEX_OPENSEARCH") = "TRUE"
    End If
    
    Call Shell.Run("%COMSPEC% /c mkdir """ & Session.Property("APPDIR") & "Data\Index\v2.11.1\""",0,true)
    Call Shell.Run("%COMSPEC% /c mkdir """ & Session.Property("APPDIR") & "Logs\""",0,true)
    
    Set objFile = objFSO.OpenTextFile("C:\OpenSearch\config\opensearch.yml", ForReading)

    fileContent = objFile.ReadAll

    objFile.Close

    Set oRE = New RegExp
    oRE.Global = True
    
    If InStrRev(fileContent, "indices.fielddata.cache.size") = 0 Then
       fileContent = fileContent & Chr(13) & Chr(10) & "indices.fielddata.cache.size: 30%"
    Else
       oRE.Pattern = "indices.fielddata.cache.size:.*"
       fileContent = oRE.Replace(fileContent, "indices.fielddata.cache.size: 30%")                           
    End if

    If InStrRev(fileContent, "indices.memory.index_buffer_size") = 0 Then
       fileContent = fileContent & Chr(13) & Chr(10) & "indices.memory.index_buffer_size: 30%"
    Else
       oRE.Pattern = "indices.memory.index_buffer_size:.*"
       fileContent = oRE.Replace(fileContent, "indices.memory.index_buffer_size: 30%")                           
    End if

    If InStrRev(fileContent, "http.max_content_length") <> 0 Then    
       oRE.Pattern = "http.max_content_length:.*"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if

    If InStrRev(fileContent, "thread_pool.index.queue_size") <> 0 Then    
       oRE.Pattern = "thread_pool.index.queue_size:.*"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if

    If InStrRev(fileContent, "thread_pool.index.size") <> 0 Then    
       oRE.Pattern = "thread_pool.index.size:.*"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if

    If InStrRev(fileContent, "thread_pool.write.queue_size") <> 0 Then    
       oRE.Pattern = "thread_pool.write.queue_size:.*"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if

    If InStrRev(fileContent, "thread_pool.write.size") <> 0 Then    
       oRE.Pattern = "thread_pool.write.size:.*"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if

    oRE.Pattern = "#path.data:.*"
    fileContent = oRE.Replace(fileContent, "path.data: " & Session.Property("APPDIR") & "Data\Index\v2.11.1\")

    oRE.Pattern = "#path.logs:.*"
    fileContent = oRE.Replace(fileContent, "path.logs: " & Session.Property("APPDIR") & "Logs\")                           
    
    If InStrRev(fileContent, "plugins.security.disabled") = 0 Then
        fileContent = fileContent & Chr(13) & Chr(10) & "plugins.security.disabled: true"
    Else
        oRE.Pattern = "plugins.security.disabled:.*"
        fileContent = oRE.Replace(fileContent, "plugins.security.disabled: true")
    End if

    Call WriteToLog("OpenSearchSetup: New config:" & fileContent)
    Call WriteToLog("OpenSearchSetup:  CommonAppDataFolder :" & "C:\OpenSearch\data")
        
    Set objFile = objFSO.OpenTextFile("C:\OpenSearch\config\opensearch.yml", ForWriting)

    objFile.WriteLine fileContent

    objFile.Close

    Set objFile = objFSO.OpenTextFile("C:\OpenSearch\config\jvm.options", ForReading)

    fileContent = objFile.ReadAll

    objFile.Close

    If InStrRev(fileContent, "-XX:+HeapDumpOnOutOfMemoryError") <> 0 Then    
       oRE.Pattern = "-XX:+HeapDumpOnOutOfMemoryError"
       fileContent = oRE.Replace(fileContent, " ")                           
    End if
    
    If InStrRev(fileContent, "-Xms") <> 0 Then
       oRE.Pattern = "-Xms.*"
       fileContent = oRE.Replace(fileContent, "-Xms4g")                           
    ElseIf InStrRev(fileContent, "-Xms4g") <> 0 Then
       fileContent = fileContent & Chr(13) & Chr(10) & "-Xms4g"
    End if

    If InStrRev(fileContent, "-Xmx") <> 0 Then
       oRE.Pattern = "-Xmx.*"
       fileContent = oRE.Replace(fileContent, "-Xmx4g")                           
    ElseIf InStrRev(fileContent, "-Xmx4g") <> 0 Then
       fileContent = fileContent & Chr(13) & Chr(10) & "-Xmx4g"
    End if

    If InStrRev(fileContent, "-Dlog4j2.formatMsgNoLookups") = 0 Then
        fileContent = fileContent & Chr(13) & Chr(10) & "-Dlog4j2.formatMsgNoLookups=true"
    Else
        oRE.Pattern = "-Dlog4j2.formatMsgNoLookups.*"
        fileContent = oRE.Replace(fileContent, "-Dlog4j2.formatMsgNoLookups=true")
    End if

    Set objFile = objFSO.OpenTextFile("C:\OpenSearch\config\jvm.options", ForWriting)

    objFile.WriteLine fileContent

    objFile.Close

    If objFSO.FileExists(OPENSEARCH_DASHBOARDS_YML) Then
        Set objFile = objFSO.OpenTextFile(OPENSEARCH_DASHBOARDS_YML, ForWriting)
        objFile.WriteLine ""
        objFile.Close
    Else
        WScript.Echo "File doesn't exist: " & OPENSEARCH_DASHBOARDS_YML
    End If

    Set objFile = objFSO.OpenTextFile(OPENSEARCH_DASHBOARDS_YML, ForReading)

    fileContent = objFile.ReadAll

    objFile.Close

    If InStrRev(fileContent, "opensearch.hosts") = 0 Then
        fileContent = fileContent & Chr(13) & Chr(10) & "opensearch.hosts: [http://localhost:9200]"
    Else
        oRE.Pattern = "opensearch.hosts:.*"
        fileContent = oRE.Replace(fileContent, "opensearch.hosts: [http://localhost:9200]")
    End if
    
    Set objFile = objFSO.OpenTextFile(OPENSEARCH_DASHBOARDS_YML, ForWriting)

    objFile.WriteLine fileContent

    objFile.Close

    Set Shell = Nothing
    
End Function

Function OpenSearchInstallPlugin
    On Error Resume Next

    Dim Shell

    Set Shell = CreateObject("WScript.Shell")

    ShellInstallCommand = """C:\OpenSearch\bin\opensearch-plugin""" & " install -b -s ingest-attachment"""
    ShellRemoveCommand = """C:\OpenSearch\bin\opensearch-plugin""" & " remove -s ingest-attachment"""
     
    Call Shell.Run("cmd /C " & """" & ShellRemoveCommand  & """",0,true)
    Call Shell.Run("cmd /C " & """" & ShellInstallCommand  & """",0,true)

    Set Shell = Nothing
    
End Function

Function TestSqlConnection
    On Error Resume Next

    Const HKLM = &H80000002 
    Dim ErrorText
    Dim Pos, keys, mysqlDriver
    Dim registry
    
    TestSqlConnection = 0
    Session.Property("SqlConnectionError") = ""

    Set registry = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    registry.EnumKey HKLM, "SOFTWARE\ODBC\ODBCINST.INI", keys
    If Not IsNull(keys) Then
        For Each key In keys
            If InStr(1, key, "MySQL ODBC", 1) <> 0 And InStr(1, key, "ANSI", 1) = 0 Then
                mysqlDriver = key
            End If
        Next
    End If

    If mysqlDriver = "" Then
        registry.EnumKey HKLM, "SOFTWARE\WOW6432Node\ODBC\ODBCINST.INI", keys
        If Not IsNull(keys) Then
            For Each key In keys
                If InStr(1, key, "MySQL ODBC", 1) <> 0 And InStr(1, key, "ANSI", 1) = 0 Then
                    mysqlDriver = key
                End If
            Next
        End If
    End If
    
    Session.Property("MYSQLODBCDRIVER") = mysqlDriver

    Set ConnectionObject = CreateObject("ADODB.Connection")
    ConnectionObject.Open "Driver={" & mysqlDriver & "};Server=" & Session.Property("DB_HOST") & ";Port=" & Session.Property("DB_PORT") & ";Uid=" & Session.Property("DB_USER") & ";Pwd=" & Session.Property("DB_PWD")
    
    If Err.Number <> 0 Then
        ErrorText = Err.Description
        Pos = InStrRev( ErrorText, "]" )
        If 0 < Pos Then
            ErrorText = Right( ErrorText, Len( ErrorText ) - Pos )
        End If
        Session.Property("SqlConnectionError") = ErrorText
    End If
    
    Set ConnectionObject = Nothing
End Function

Function OpenRestySetup
   On Error Resume Next

   Dim objShell, sourcePath, destinationPath, openRestyServicePath, openRestyFolder, objFSO, objFolder

   Set objShell = CreateObject("WScript.Shell")

   destinationPath = Session.Property("APPDIR")
   openRestyServicePath = Session.Property("APPDIR") & "tools\OpenResty.exe"
   openRestyFolder = ""
   Set objFSO = CreateObject("Scripting.FileSystemObject")
    For Each objFolder In objFSO.GetFolder(destinationPath).SubFolders
        If Left(objFolder.Name, 9) = "openresty" Then
          openRestyFolder = objFolder.Name
        End If
    Next
    Set objFSO = Nothing

   sourcePath = Session.Property("APPDIR") & openRestyFolder

   ' Run XCopy to copy files and folders
   objShell.Run "xcopy """ & sourcePath & """ """ & destinationPath & """ /E /I /Y", 0, True

   objShell.CurrentDirectory = destinationPath

   ' Run the RMDIR command to delete the folder
   objShell.Run "cmd /c RMDIR /S /Q """ & openRestyFolder & """", 0, True

   objShell.Run """" & openRestyServicePath & """ install", 0, True

   Set objShell = Nothing

End Function

Function OpenSearchStackSetup
    On Error Resume Next

    Dim ToolsFolder, OpenSearchDashboardsDir, OpenSearchDashboardsService, OpenSearchDashboardsPlugin, RemoveOSDSecurity, FluentBitDir, FluentBitService

    Set objShell = CreateObject("WScript.Shell")

    ToolsFolder = Session.Property("APPDIR") & "tools\"
    OpenSearchDashboardsDir = Session.Property("APPDIR") & "opensearch-dashboards-2.11.1\"
    OpenSearchDashboardsService = OpenSearchDashboardsDir & "winsw\OpenSearchDashboards.exe"
    OpenSearchDashboardsPlugin = OpenSearchDashboardsDir & "bin\opensearch-dashboards-plugin.bat"
    FluentBitDir = Session.Property("APPDIR") & "fluent-bit-2.2.2-win64\"

    FluentBitService = "sc.exe create Fluent-Bit binpath= """ & "\""" & FluentBitDir & "bin\fluent-bit.exe\"" -c \""" & FluentBitDir & "conf\fluent-bit.conf\""""" & " start=delayed-auto"
    Call objShell.Run("cmd /C " & """" & FluentBitService  & """",0,true)

    RemoveOSDSecurity = """" & OpenSearchDashboardsPlugin & """ remove securityDashboards"
    Call objShell.Run("cmd /C " & """" & RemoveOSDSecurity  & """",0,true)

    objShell.Run "xcopy """ & ToolsFolder & "\OpenSearchDashboards*"" """ & OpenSearchDashboardsDir & "winsw\"" /E /I /Y", 0, True

    objShell.Run """" & OpenSearchDashboardsService & """ install", 0, True
    objShell.Run """" & OpenSearchDashboardsService & """ start", 0, True

    objShell.Run "cmd /c RMDIR /S /Q """ & ToolsFolder & """", 0, True

    Set objShell = Nothing

End Function

Function MoveConfigs
    On Error Resume Next

    Dim objFSO, objShell, sourceFolder, targetFolder, nginxFolder, configFile, configSslFile, sslScriptPath, sslCertPath, sslCertKeyPath, psCommand, FluentBitSourceFile, FluentBitDstFolder

    ' Define source and target paths
    Set objFSO = CreateObject("Scripting.FileSystemObject")
    Set objShell = CreateObject("WScript.Shell")
    sourceFolder = Session.Property("APPDIR") & "nginx\conf"
    targetFolder = "C:\OpenResty\conf"
    nginxFolder =  Session.Property("APPDIR") & "nginx"
    configSslFile = targetFolder & "\onlyoffice-proxy-ssl.conf.tmpl"
    configFile = targetFolder & "\onlyoffice-proxy.conf"
    sslScriptPath = Session.Property("APPDIR") & "sbin\docspace-ssl-setup.ps1"
    FluentBitSourceFile = Session.Property("APPDIR") & "fluent-bit.conf"
    FluentBitDstFolder = "C:\OpenSearchStack\fluent-bit-2.2.2-win64\conf\"

    ' Read content and extract SSL certificate and key paths if it exists
    If objFSO.FileExists(configFile) Then
        content = ReadFile(configFile, objFSO)
        sslCertPath = ExtractPath(content, "ssl_certificate\s+(.*?);", objFSO)
        sslCertKeyPath = ExtractPath(content, "ssl_certificate_key\s+(.*?);", objFSO)
    Else
        WScript.Echo "Configuration file not found!"
    End If

    ' Check if source folder exists
    If objFSO.FolderExists(sourceFolder) Then
        ' Check if target folder exists, if not, create it
        If Not objFSO.FolderExists(targetFolder) Then
            objFSO.CreateFolder(targetFolder)
        End If

        ' Copy files and folders from source to target
        CopyFolderContents objFSO.GetFolder(sourceFolder), targetFolder, objFSO

        ' Delete source folder
        objFSO.DeleteFolder nginxFolder, True ' "True" parameter for recursive deletion

        WScript.Echo "Files and folders moved, and source folder deleted."
    Else
        WScript.Echo "Source folder does not exist."
    End If

    ' If SSL path variables are present, set the SSL paths
    If objFSO.FileExists(configSslFile) And ((Len(Trim(sslCertPath)) > 0) And (Len(Trim(sslCertKeyPath)) > 0)) Then
        psCommand = "powershell -File """ & sslScriptPath & """ -f """ & sslCertPath & """ """ & sslCertKeyPath & """"
        objShell.Run psCommand, 0, True
    Else
        WScript.Echo "Source file not found."
    End If

    ' Delete
    If objFSO.FileExists(FluentBitDstFolder & "fluent-bit.conf") Then
        objFSO.DeleteFile FluentBitDstFolder & "fluent-bit.conf", True
        If objFSO.FileExists(FluentBitSourceFile) Then
            objFSO.MoveFile FluentBitSourceFile, FluentBitDstFolder
        End If
    End If

    Set objFSO = Nothing
    Set objShell = Nothing
End Function

Function ReadFile(filePath, objFSO)
    Dim objFile
    If objFSO.FileExists(filePath) Then
        Set objFile = objFSO.OpenTextFile(filePath, 1)
        ReadFile = objFile.ReadAll
        objFile.Close
    Else
        WScript.Echo "File not found: " & filePath
    End If
End Function

Function ExtractPath(content, pattern, objFSO)
    Dim regex, match
    Set regex = New RegExp
    regex.Pattern = pattern

    Set match = regex.Execute(content)
    If match.Count > 0 Then
        ExtractPath = match(0).Submatches(0)
    Else
        WScript.Echo "Path not found in the content."
        ExtractPath = Null
    End If
End Function

Sub CopyFolderContents(sourceFolder, targetFolder, objFSO)
    Dim subFolder, objFile

    ' Copy files
    For Each objFile In sourceFolder.Files
        objFSO.CopyFile objFile.Path, targetFolder & "\" & objFile.Name, True
    Next

    ' Recursively copy subfolders
    For Each subFolder In sourceFolder.SubFolders
        Dim newTargetFolder
        newTargetFolder = targetFolder & "\" & subFolder.Name
        objFSO.CreateFolder newTargetFolder
        CopyFolderContents subFolder, newTargetFolder, objFSO
    Next
End Sub

Function EnterpriseConfigure
    On Error Resume Next

    Const HKLM = &H80000002

    Dim strKeyPath, strValueName, strNewDisplayName

    strKeyPath = "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\ONLYOFFICE DocSpace Community " & Session.Property("ProductVersion") 
    strValueName = "DisplayName"
    strNewDisplayName = Session.Property("ProductName")

    Set registry = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    registry.SetStringValue HKLM, strKeyPath, strValueName, strNewDisplayName

End Function

Function ReadIni( myFilePath, mySection, myKey )
    ' This function returns a value read from an INI file
    '
    ' Arguments:
    ' myFilePath  [string]  the (path and) file name of the INI file
    ' mySection   [string]  the section in the INI file to be searched
    ' myKey       [string]  the key whose value is to be returned
    '
    ' Returns:
    ' the [string] value for the specified key in the specified section
    '
    ' CAVEAT:     Will return a space if key exists but value is blank
    '
    ' Written by Keith Lacelle
    ' Modified by Denis St-Pierre and Rob van der Woude

    Const ForReading   = 1
    Const ForWriting   = 2
    Const ForAppending = 8

    Dim intEqualPos
    Dim objFSO, objIniFile
    Dim strFilePath, strKey, strLeftString, strLine, strSection

    Set objFSO = CreateObject( "Scripting.FileSystemObject" )

    ReadIni     = ""
    strFilePath = Trim( myFilePath )
    strSection  = Trim( mySection )
    strKey      = Trim( myKey )

    If objFSO.FileExists( strFilePath ) Then
        Set objIniFile = objFSO.OpenTextFile( strFilePath, ForReading, False )
        Do While objIniFile.AtEndOfStream = False
            strLine = Trim( objIniFile.ReadLine )

            ' Check if section is found in the current line
            If LCase( strLine ) = "[" & LCase( strSection ) & "]" Then
                strLine = Trim( objIniFile.ReadLine )

                ' Parse lines until the next section is reached
                Do While Left( strLine, 1 ) <> "["
                    ' Find position of equal sign in the line
                    intEqualPos = InStr( 1, strLine, "=", 1 )
                    If intEqualPos > 0 Then
                        strLeftString = Trim( Left( strLine, intEqualPos - 1 ) )
                        ' Check if item is found in the current line
                        If LCase( strLeftString ) = LCase( strKey ) Then
                            ReadIni = Trim( Mid( strLine, intEqualPos + 1 ) )
                            ' In case the item exists but value is blank
                            If ReadIni = "" Then
                                ReadIni = " "
                            End If
                            ' Abort loop when item is found
                            Exit Do
                        End If
                    End If

                    ' Abort if the end of the INI file is reached
                    If objIniFile.AtEndOfStream Then Exit Do

                    ' Continue with next line
                    strLine = Trim( objIniFile.ReadLine )
                Loop
            Exit Do
            End If
        Loop
        objIniFile.Close
    Else
        WScript.Echo strFilePath & " doesn't exists. Exiting..."
        Wscript.Quit 1
    End If
End Function

Sub WriteIni( myFilePath, mySection, myKey, myValue )
    ' This subroutine writes a value to an INI file
    '
    ' Arguments:
    ' myFilePath  [string]  the (path and) file name of the INI file
    ' mySection   [string]  the section in the INI file to be searched
    ' myKey       [string]  the key whose value is to be written
    ' myValue     [string]  the value to be written (myKey will be
    '                       deleted if myValue is <DELETE_THIS_VALUE>)
    '
    ' Returns:
    ' N/A
    '
    ' CAVEAT:     WriteIni function needs ReadIni function to run
    '
    ' Written by Keith Lacelle
    ' Modified by Denis St-Pierre, Johan Pol and Rob van der Woude

    Const ForReading   = 1
    Const ForWriting   = 2
    Const ForAppending = 8

    Dim blnInSection, blnKeyExists, blnSectionExists, blnWritten
    Dim intEqualPos
    Dim objFSO, objNewIni, objOrgIni, wshShell
    Dim strFilePath, strFolderPath, strKey, strLeftString
    Dim strLine, strSection, strTempDir, strTempFile, strValue

    strFilePath = Trim( myFilePath )
    strSection  = Trim( mySection )
    strKey      = Trim( myKey )
    strValue    = Trim( myValue )

    Set objFSO   = CreateObject( "Scripting.FileSystemObject" )
    Set wshShell = CreateObject( "WScript.Shell" )

    strTempDir  = wshShell.ExpandEnvironmentStrings( "%TEMP%" )
    strTempFile = objFSO.BuildPath( strTempDir, objFSO.GetTempName )

    Set objOrgIni = objFSO.OpenTextFile( strFilePath, ForReading, True )
    Set objNewIni = objFSO.CreateTextFile( strTempFile, False, False )

    blnInSection     = False
    blnSectionExists = False
    ' Check if the specified key already exists
    blnKeyExists     = ( ReadIni( strFilePath, strSection, strKey ) <> "" )
    blnWritten       = False

    ' Check if path to INI file exists, quit if not
    strFolderPath = Mid( strFilePath, 1, InStrRev( strFilePath, "\" ) )
    If Not objFSO.FolderExists ( strFolderPath ) Then
        WScript.Echo "Error: WriteIni failed, folder path (" _
                   & strFolderPath & ") to ini file " _
                   & strFilePath & " not found!"
        Set objOrgIni = Nothing
        Set objNewIni = Nothing
        Set objFSO    = Nothing
        WScript.Quit 1
    End If

    While objOrgIni.AtEndOfStream = False
        strLine = Trim( objOrgIni.ReadLine )
        If blnWritten = False Then
            If LCase( strLine ) = "[" & LCase( strSection ) & "]" Then
                blnSectionExists = True
                blnInSection = True
            ElseIf InStr( strLine, "[" ) = 1 Then
                blnInSection = False
            End If
        End If

        If blnInSection Then
            If blnKeyExists Then
                intEqualPos = InStr( 1, strLine, "=", vbTextCompare )
                If intEqualPos > 0 Then
                    strLeftString = Trim( Left( strLine, intEqualPos - 1 ) )
                    If LCase( strLeftString ) = LCase( strKey ) Then
                        ' Only write the key if the value isn't empty
                        ' Modification by Johan Pol
                        If strValue <> "<DELETE_THIS_VALUE>" Then
                            objNewIni.WriteLine strKey & "=" & strValue
                        End If
                        blnWritten   = True
                        blnInSection = False
                    End If
                End If
                If Not blnWritten Then
                    objNewIni.WriteLine strLine
                End If
            Else
                objNewIni.WriteLine strLine
                    ' Only write the key if the value isn't empty
                    ' Modification by Johan Pol
                    If strValue <> "<DELETE_THIS_VALUE>" Then
                        objNewIni.WriteLine strKey & "=" & strValue
                    End If
                blnWritten   = True
                blnInSection = False
            End If
        Else
            objNewIni.WriteLine strLine
        End If
    Wend

    If blnSectionExists = False Then ' section doesn't exist
        objNewIni.WriteLine
        objNewIni.WriteLine "[" & strSection & "]"
            ' Only write the key if the value isn't empty
            ' Modification by Johan Pol
            If strValue <> "<DELETE_THIS_VALUE>" Then
                objNewIni.WriteLine strKey & "=" & strValue
            End If
    End If

    objOrgIni.Close
    objNewIni.Close

    ' Delete old INI file
    objFSO.DeleteFile strFilePath, True
    ' Rename new INI file
    objFSO.CopyFile strTempFile, strFilePath, True

    objFSO.DeleteFile strTempFile, True

    Set objOrgIni = Nothing
    Set objNewIni = Nothing
    Set objFSO    = Nothing
    Set wshShell  = Nothing
End Sub
