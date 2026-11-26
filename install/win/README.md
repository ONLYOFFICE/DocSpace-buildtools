# ONLYOFFICE Apps for Windows

ONLYOFFICE Apps for Windows Server is installed from two EXE files:

- `ONLYOFFICE_Apps_<Edition>_Win-install.exe` (Community, Enterprise or Developer): ONLYOFFICE Apps with ONLYOFFICE Docs of the
  same edition; it also installs the missing third-party components (.NET, Java, Node.js, MySQL, PostgreSQL, RabbitMQ, Redis,
  OpenResty, OpenSearch and others).
- `ONLYOFFICE_Apps_Prerequisites_Win-install.exe`: the same third-party components packed inside the EXE, for servers without
  internet access.

Download:
[Community](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Community_Win-install.latest.exe),
[Enterprise](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Enterprise_Win-install.latest.exe),
[Prerequisites](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Prerequisites_Win-install.latest.exe).
The step-by-step guide with screenshots is on the
[ONLYOFFICE website](https://guides.onlyoffice.com/installation/docspace-community-install-windows.aspx).

## Requirements

- Windows Server 2016 or newer, 64-bit.
- An administrator account.
- Free ports 80 and 443.
- Internet access, or the Prerequisites EXE run first.

## Installation

*(Optional)* On a server without internet access, first run `ONLYOFFICE_Apps_Prerequisites_Win-install.exe`: it installs the
third-party components that the edition EXE otherwise downloads.

1. Run `ONLYOFFICE_Apps_<Edition>_Win-install.exe` as an administrator and follow the wizard. The default connections fit
   MySQL, PostgreSQL, RabbitMQ, Redis and OpenSearch installed on the same server; enter other addresses to use external ones.
2. Open `http://<server address>/` and create the administrator of the portal.

Apps is installed into `C:\Program Files (x86)\Ascensio System SIA\Apps` by default. **Enterprise and Developer** read the
license from `Data\license.lic` in that folder.

A new installation replaces the default MySQL `root` and PostgreSQL passwords with random ones and creates its own MySQL and
RabbitMQ users with random passwords; passwords you enter are kept. They are saved in the registry key `HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Ascensio System SIA\ONLYOFFICE Apps`, readable
by administrators only.

## Unattended installation

Run the EXE from an elevated command prompt. The EXE options go **first**, the Windows Installer options after them:

```bat
ONLYOFFICE_Apps_Prerequisites_Win-install.exe /exenoui /exelog prereq.exe.log /qn /norestart /L*V prereq.msi.log
ONLYOFFICE_Apps_Community_Win-install.exe /exenoui /exelog apps.exe.log /qn /norestart /L*V apps.msi.log
```

Exit code `0` means success, `3010` success with a restart required, `1603` a failure (see the `.msi.log`).

Settings are passed as `NAME=value` at the end, for example `APP_PORT=8080 DB_HOST=db.example.com DB_PWD=secret`:

| Property | Default | Meaning |
|---|---|---|
| `APPDIR` | `C:\Program Files (x86)\Ascensio System SIA\Apps\` | installation folder |
| `APP_PORT` | `80` | HTTP port of the portal |
| `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PWD` | `localhost`, `3306`, `onlyoffice`, `root`, `root` | MySQL |
| `PS_DB_HOST`, `PS_DB_PORT`, `PS_DB_NAME`, `PS_DB_USER`, `PS_DB_PWD` | `localhost`, `5432`, `onlyoffice`, `onlyoffice`, `onlyoffice` | PostgreSQL of ONLYOFFICE Docs |
| `AMQP_HOST`, `AMQP_PORT`, `AMQP_USER`, `AMQP_PWD`, `AMQP_VHOST` | `localhost`, `5672`, `guest`, `guest`, `/` | RabbitMQ |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PWD` | `localhost`, `6379`, empty | Redis |
| `OPENSEARCH_SCHEME`, `OPENSEARCH_HOST`, `OPENSEARCH_PORT` | `http`, `localhost`, `9200` | OpenSearch |
| `DOCUMENT_SERVER_PORT` | `8083` | port of ONLYOFFICE Docs |
| `DOCUMENT_SERVER_JWT_SECRET` | generated | JWT secret shared by Apps and Docs |

## HTTPS

Run `apps-ssl-setup.ps1` from the `sbin` folder of the installation in an elevated PowerShell:

```powershell
cd "C:\Program Files (x86)\Ascensio System SIA\Apps\sbin"
.\apps-ssl-setup.ps1 admin@example.com apps.example.com                       # Let's Encrypt certificate
.\apps-ssl-setup.ps1 -f apps.example.com C:\certs\apps.pem C:\certs\apps.key  # own certificate
.\apps-ssl-setup.ps1 -d                                                       # back to plain HTTP
```

Let's Encrypt needs the domain to point to the server and port 80 to be reachable from the internet; the certificate is
renewed automatically.

## Services and logs

Apps runs as Windows services named `Apps.*`. Restart them with `Get-Service Apps.* | Restart-Service` in an elevated
PowerShell. The logs are in the `Logs` folder of the installation.

## Update and removal

- **Update:** run the EXE of the new version of the same edition; data, settings and passwords are kept. Without internet
  access, run the new Prerequisites EXE first.
- **Removal:** remove `ONLYOFFICE Apps <Edition>` in *Settings → Apps*. ONLYOFFICE Docs and the third-party components stay
  installed; remove them the same way if they are not needed.

## Support

- Community forum: https://forum.onlyoffice.com
- Help desk (Enterprise and Developer): https://helpdesk.onlyoffice.com
