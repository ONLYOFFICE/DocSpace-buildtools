# ONLYOFFICE Apps for Windows

ONLYOFFICE Apps for Windows Server is installed from two EXE files:

| Installer | What it installs |
|---|---|
| `ONLYOFFICE_Apps_<Edition>_Win-install.exe` (Community, Enterprise or Developer) | ONLYOFFICE Apps, ONLYOFFICE Docs of the same edition, OpenResty, OpenSearch and OpenSearch Dashboards with Fluent Bit |
| `ONLYOFFICE_Apps_Prerequisites_Win-install.exe` | the third-party components Apps needs, packed inside the EXE, for servers without internet access |

Latest versions:
[Community](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Community_Win-install.latest.exe),
[Enterprise](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Enterprise_Win-install.latest.exe),
[Prerequisites](https://download.onlyoffice.com/apps/windows/ONLYOFFICE_Apps_Prerequisites_Win-install.latest.exe).
The step-by-step guide with screenshots is on the
[ONLYOFFICE website](https://guides.onlyoffice.com/installation/docspace-community-install-windows.aspx).

## Requirements

- **Windows Server 2016 or newer, 64-bit.** The installer refuses desktop Windows (10, 11) and Windows Server 2012 R2 or older.
- An administrator account.
- Free ports 80 and 443. The installer opens them in Windows Firewall for OpenResty, which serves the portal.
- Internet access, or the Prerequisites EXE run first (see below).

## Third-party components

Apps uses the components below. The edition EXE installs the missing ones before Apps; a server without internet access
gets them from the Prerequisites EXE.

| Component | Version |
|---|---|
| .NET Runtime and ASP.NET Core Runtime | 10.0 |
| .NET Framework | 4.8 |
| OpenJDK | 25.0.3 |
| Node.js | 24.22.3 |
| MySQL Community Server, MySQL Connector/ODBC | 8.4.3, 8.4.0 |
| PostgreSQL (for ONLYOFFICE Docs) | 14.0 |
| RabbitMQ, Erlang | 3.12.1, 26.0.2 |
| Redis | 7.4.0 |
| OpenResty | 1.27.1.1 |
| OpenSearch, OpenSearch Dashboards | 3.5.0 |
| FFmpeg, FireDaemon OpenSSL 3, Certbot | 6.0, 3.3.0, 2.6.0 |
| Visual C++ Redistributable | 2013 x64, 2015-2019 x86 and x64 |

MySQL, PostgreSQL, RabbitMQ, Redis and OpenSearch may also run on other servers: enter their addresses in the wizard or
pass them as properties (see [Unattended installation](#unattended-installation)).

## Installation

1. Without internet access only: run `ONLYOFFICE_Apps_Prerequisites_Win-install.exe` and finish it.
2. Run `ONLYOFFICE_Apps_<Edition>_Win-install.exe` as an administrator and follow the wizard. It asks for the installation
   folder and for the MySQL, PostgreSQL, RabbitMQ and OpenSearch connections; the defaults fit the components installed on the
   same server.
3. Open `http://<server address>/` and create the administrator of the portal.

By default Apps is installed into `C:\Program Files (x86)\Ascensio System SIA\Apps` and ONLYOFFICE Docs into
`C:\Program Files (x86)\Ascensio System SIA\DocumentServer`, next to it. Docs is installed only when no suitable Docs is on the
server yet.

**Enterprise and Developer** need a license: Apps reads it from `Data\license.lic` in the installation folder and passes the
same path to ONLYOFFICE Docs.

### Passwords

On a new installation the installer replaces the default passwords with random ones: the MySQL `root` password, a dedicated
MySQL user for the Apps database, the PostgreSQL passwords and a RabbitMQ user for Apps and Docs. Passwords you enter in the
wizard or pass as properties are kept as they are. The values are saved in the registry key
`HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Ascensio System SIA\ONLYOFFICE Apps`, which only SYSTEM and Administrators can read;
the installation folder is locked the same way.

## Unattended installation

Run the EXE from an elevated command prompt. The EXE options go **first**, the Windows Installer options after them,
otherwise the EXE shows an error window and waits:

```bat
ONLYOFFICE_Apps_Prerequisites_Win-install.exe /exenoui /exelog prereq.exe.log /qn /norestart /L*V prereq.msi.log
ONLYOFFICE_Apps_Community_Win-install.exe /exenoui /exelog apps.exe.log /qn /norestart /L*V apps.msi.log
```

Exit code `0` means success, `3010` success with a restart required before the next installer, `1603` a failure: search
the `.msi.log` for `Return value 3`.

Settings are passed as `NAME=value` after the options, for example
`ONLYOFFICE_Apps_Community_Win-install.exe /exenoui /qn /norestart APP_PORT=8080 DB_HOST=db.example.com DB_PWD=secret`.

| Property | Default | Meaning |
|---|---|---|
| `APPDIR` | `C:\Program Files (x86)\Ascensio System SIA\Apps\` | installation folder |
| `APP_PORT` | `80` | HTTP port of the portal |
| `DB_HOST`, `DB_PORT`, `DB_NAME` | `localhost`, `3306`, `onlyoffice` | MySQL server and database of Apps |
| `DB_USER`, `DB_PWD` | `root`, `root` | MySQL account; with the default password a random one is set, see [Passwords](#passwords) |
| `PS_DB_HOST`, `PS_DB_PORT`, `PS_DB_NAME`, `PS_DB_USER`, `PS_DB_PWD` | `localhost`, `5432`, `onlyoffice`, `onlyoffice`, `onlyoffice` | PostgreSQL database of ONLYOFFICE Docs |
| `AMQP_HOST`, `AMQP_PORT`, `AMQP_USER`, `AMQP_PWD`, `AMQP_VHOST` | `localhost`, `5672`, `guest`, `guest`, `/` | RabbitMQ |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PWD` | `localhost`, `6379`, empty | Redis |
| `OPENSEARCH_SCHEME`, `OPENSEARCH_HOST`, `OPENSEARCH_PORT` | `http`, `localhost`, `9200` | OpenSearch |
| `DOCUMENT_SERVER_PORT` | `8083` | port of ONLYOFFICE Docs installed with Apps |
| `DOCUMENT_SERVER_JWT_SECRET` | generated, or taken from an installed ONLYOFFICE Docs | JWT secret shared by Apps and Docs |

## HTTPS

`apps-ssl-setup.ps1` in the `sbin` folder of the installation configures HTTPS in OpenResty. Run it from that folder in an
elevated PowerShell:

```powershell
cd "C:\Program Files (x86)\Ascensio System SIA\Apps\sbin"
.\apps-ssl-setup.ps1 admin@example.com apps.example.com                       # Let's Encrypt certificate
.\apps-ssl-setup.ps1 -f apps.example.com C:\certs\apps.pem C:\certs\apps.key  # own certificate (PEM, PFX, DER, CER, PKCS#7)
.\apps-ssl-setup.ps1 -d                                                       # back to plain HTTP
```

Let's Encrypt needs the domain to point to the server and port 80 to be reachable from the internet; the script also adds the
weekly scheduled task *Certbot renew* that renews the certificate. Certbot and OpenSSL come with the third-party components.

## Services

Apps runs as Windows services named `Apps.*` (`Apps.WebApi`, `Apps.WebStudio`, `Apps.Login`, `Apps.DocEditor`,
`Apps.Socket.IO` and others) under `NT AUTHORITY\LocalService`; OpenResty, OpenSearch, OpenSearch Dashboards, MySQL,
RabbitMQ, Redis and ONLYOFFICE Docs run as their own services. Restart Apps with
`Get-Service Apps.* | Restart-Service` in an elevated PowerShell. The logs of the services are in the `Logs` folder of the
installation.

## Update and removal

- **Update:** run the EXE of the new version of the same edition. It keeps the data, the settings and the passwords of the
  installed version. Run the new Prerequisites EXE first on a server without internet access.
- **Removal:** remove `ONLYOFFICE Apps <Edition>` in *Settings → Apps* (or *Programs and Features*). ONLYOFFICE Docs and the
  third-party components are separate programs and stay installed; remove them the same way if they are not needed.

## Support

- Community forum: https://forum.onlyoffice.com
- Help desk (Enterprise and Developer): https://helpdesk.onlyoffice.com

Building the installers from this repository is described in [BUILDING.md](BUILDING.md).
