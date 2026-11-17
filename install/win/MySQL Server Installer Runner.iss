#define BASE_DIR                '{commonpf}/MySQL/MySQL Server 8.4'
#define DATA_DIR                '{commonpf}/MySQL/MySQL Server 8.4/data'

[Setup]
AppName=MySQL Installer Runner
AppVersion=0.1.0
AppCopyright=© Ascensio System SIA 2019. All rights reserved
AppPublisher=Ascensio System SIA
AppPublisherURL=https://www.onlyoffice.com/
VersionInfoVersion=0.1.0
DefaultDirName={commonpf}\MySQL Installer Runner
DefaultGroupName=MySQL Installer Runner
CreateUninstallRegKey=no
Uninstallable=no
OutputBaseFilename="MySQL Installer Runner"
OutputDir=/
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Run]
Filename: "{#BASE_DIR}\bin\mysqld.exe"; Parameters: "--initialize-insecure"; Flags: runhidden waituntilterminated
Filename: "cmd"; Parameters: "/C move /Y ""{tmp}\my.ini"" ""{#DATA_DIR}\my.ini"""; Flags: runhidden waituntilterminated
Filename: "{#BASE_DIR}\bin\mysqld.exe"; Parameters: "--install MySQL84 --defaults-file=""{#DATA_DIR}\my.ini"""; Flags: runhidden waituntilterminated
Filename: "net"; Parameters: "start MySQL84"; Flags: runhidden waituntilterminated
Filename: "{#BASE_DIR}\bin\mysql.exe"; Parameters: "-u root -e ""source {code:GetRootPasswordSqlPath}"""; Flags: runhidden waituntilterminated; BeforeInstall: SaveRootPasswordSql; AfterInstall: DeleteRootPasswordSql

[Code]
function SaveMyIniFile(BaseDir, DataDir: String): Boolean;
var
  FileName: String;
  Content: String;
begin
  FileName := ExpandConstant('{tmp}\my.ini');

    Content := Format(
    '[mysqld]' + #13#10 +
    'basedir=%s' + #13#10 +
    'datadir=%s' + #13#10 +
    'port=3306' + #13#10 +
    'sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES' + #13#10,[BaseDir, DataDir]);

  Result := SaveStringToFile(FileName, Content, False);
end;

// The root password goes through a file in the private setup temp dir, so it never appears in a command line
function GetRootPasswordSqlPath(Param: String): String;
begin
  Result := ExpandConstant('{tmp}\set-root-password.sql');
  StringChangeEx(Result, '\', '/', True);
end;

procedure SaveRootPasswordSql;
var
  Password: String;
begin
  Password := ExpandConstant('{param:DB_PWD}');
  StringChangeEx(Password, '\', '\\', True);
  StringChangeEx(Password, '''', '''''', True);
  SaveStringToFile(ExpandConstant('{tmp}\set-root-password.sql'), 'ALTER USER ''root''@''localhost'' IDENTIFIED BY ''' + Password + ''';' + #13#10, False);
end;

procedure DeleteRootPasswordSql;
begin
  DeleteFile(ExpandConstant('{tmp}\set-root-password.sql'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    SaveMyIniFile(ExpandConstant('{#BASE_DIR}'), ExpandConstant('{#DATA_DIR}'));
  end;
end;
