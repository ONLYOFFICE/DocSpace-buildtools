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
; The bootstrap root password is set from a file in the per-user {tmp} folder, so it never appears in a command line.
; Apps replaces it with a random password once its installation is committed (SecureDatabaseSuperusers in utils.ps1).
Filename: "{#BASE_DIR}\bin\mysqld.exe"; Parameters: "--initialize-insecure --init-file=""{tmp}\mysql-init.sql"""; Flags: runhidden waituntilterminated
Filename: "cmd"; Parameters: "/C move /Y ""{tmp}\my.ini"" ""{#DATA_DIR}\my.ini"""; Flags: runhidden waituntilterminated
Filename: "{#BASE_DIR}\bin\mysqld.exe"; Parameters: "--install MySQL84 --defaults-file=""{#DATA_DIR}\my.ini"""; Flags: runhidden waituntilterminated
Filename: "net"; Parameters: "start MySQL84"; Flags: runhidden waituntilterminated

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

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssInstall then
  begin
    SaveMyIniFile(ExpandConstant('{#BASE_DIR}'), ExpandConstant('{#DATA_DIR}'));
    // The password must match $MySqlBootstrapRootPassword in utils.ps1.
    SaveStringToFile(ExpandConstant('{tmp}\mysql-init.sql'), 'ALTER USER ''root''@''localhost'' IDENTIFIED BY ''root'';', False);
  end;
end;
