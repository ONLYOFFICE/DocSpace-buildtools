[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![Docker Pulls](https://img.shields.io/docker/pulls/onlyoffice/apps-files?logo=docker)](https://hub.docker.com/r/onlyoffice/apps-files)
[![Docker Image Version](https://img.shields.io/docker/v/onlyoffice/apps-files?sort=semver&logo=docker)](https://hub.docker.com/r/onlyoffice/apps-files/tags)
[![GitHub Stars](https://img.shields.io/github/stars/ONLYOFFICE/DocSpace-buildtools?style=flat&logo=github)](https://github.com/ONLYOFFICE/DocSpace-buildtools/stargazers)

# ONLYOFFICE Apps - OneClickInstall

A simple self-hosted installer for **ONLYOFFICE Apps** using Docker or Linux packages.

| 🚀 [Start](#-quick-start) | 🛠 [Flags](#-flags) | 💡 [Examples](#-examples) | 🖥️ [Reqs](#-system-requirements) | ✅ [OS](#-supported-operating-systems) | 📚 [Resources](#-additional-resources) | 📝 [License](#-license) |
|--------------------------|--------------------------------------------|---------------------------|----------------------------------------|----------------------------------------|----------------------------------------|----------------------|

**ONLYOFFICE Apps** is a room-based collaborative platform which allows organizing a clear file structure depending on users' needs or project goals. Flexible access  permissions and user roles allow fine-tuning the access to the whole space or separate rooms.

## 🚀 Quick Start

### 1. Download the installer

Community Edition (default):

```bash
curl -O https://download.onlyoffice.com/apps/apps-install.sh
```

If you want to install a different edition, choose one of the following:

> **Enterprise Edition:**
> ```bash
> curl -O https://download.onlyoffice.com/apps/apps-enterprise-install.sh
> ```

> **Developer Edition:**
> ```bash
> curl -O https://download.onlyoffice.com/apps/apps-developer-install.sh
> ```

### 2. Run the script
Use the downloaded script to install ONLYOFFICE Apps with either the RPM/DEB package or Docker.  

**Install as RPM/DEB Package**:
```bash
sudo bash <script-name> package
```

**Install via Docker**:
```bash
sudo bash <script-name> docker
```

Replace `<script-name>` with the name of the downloaded script (e.g., `apps-enterprise-install.sh`).

## 🛠 Flags

All scripts support `-h` to show available flags. View available options with:

**For Docker installation**:
```bash
sudo bash <script-name> docker -h
```
**For DEB/RPM package installation**:
```bash
sudo bash <script-name> package -h
```

### Common flags
> Works for both Docker and package installations

| Flag                   | Value placeholder                          | Default value      | Description                           |
|------------------------|--------------------------------------------|--------------------|---------------------------------------|
| `--installationtype`   | `community` \| `developer` \| `enterprise` | `enterprise`       | Choose the edition                    |
| `--update`             | `true` \| `false`                          | `false`            | Update existing containers / packages |
| `--skiphardwarecheck`  | `true` \| `false`                          | `false`            | Skip CPU/RAM/Disk checks              |
| `--makeswap`           | `true` \| `false`                          | `true`             | Create a swap file automatically      |
| `--uninstall`          | `true` \| `false`                          | `false`            | Remove an existing installation       |
| `--jwtheader`          | `<HEADER>`                                 | `AuthorizationJwt` | HTTP header used to pass the JWT      |
| `--jwtsecret`          | `<SECRET>`                                 | *(auto-generated)* | Secret key for JWT validation         |
| `--installfluentbit`   | `true` \| `false`                          | `true`             | Install / update Fluent Bit           |
| `--dashboardsusername` | `<USER>`                                   | `onlyoffice`       | Username for `/dashboards/`           |
| `--dashboardspassword` | `<PASS>`                                   | *(auto-generated)* | Password for `/dashboards/`           |
| `--localscripts`       | `true` \| `false`                          | `false`            | Run local scripts                     |

### Docker-specific flags
> Applies only to Docker installation

#### Registry & Images
| Flag                    | Value placeholder                         | Default value             | Description                    |
|-------------------------|-------------------------------------------|---------------------------|--------------------------------|
| `--registry`            | `<URL>`                                   | -                         | Docker registry URL            |
| `--username`            | `<USER>`                                  | -                         | Registry login                 |
| `--password`            | `<PASS>`                                  | -                         | Registry password              |
| `--volumesdir`          | `<DIR>`                                   | `/var/lib/docker/volumes` | Host dir for Docker volumes    |
| `--basedir`             | `<DIR>`                                   | `/app/onlyoffice` (`~/onlyoffice` on macOS) | Dir for configuration files; must be empty or hold an existing installation |

#### ONLYOFFICE Apps Core
| Flag                    | Value placeholder                         | Default value             | Description                    |
|-------------------------|-------------------------------------------|---------------------------|--------------------------------|
| `--installapps`     | `true` \| `false`                         | `true`                    | Install / update ONLYOFFICE Apps      |
| `--deployment-mode`     | `standalone` \| `stack` \| `microservices` | `standalone`              | Deployment topology (see below)|
| `--appsversion`     | `<VERSION>`                               | *(latest stable)*         | ONLYOFFICE Apps version               |
| `--appshost`        | `<HOST>`                                  | `localhost`               | Hostname / IP                  |
| `--externalport`        | `<PORT>`                                  | `80`                      | External HTTP port             |
| `--machinekey`          | `<KEY>`                                   | *(auto-generated)*        | `core.machinekey` value        |

`--deployment-mode` selects how ONLYOFFICE Apps is deployed via Docker:
- `microservices` — modular multi-container deployment, one container per service.
- `stack` — services grouped into fewer containers sharing a common runtime.
- `standalone` — a single all-in-one `onlyoffice-apps` container (plus MySQL, OpenSearch and
  Document Server, each replaceable by an external one). Runs as a single node: cache and queues
  are in-process, so it cannot be scaled out horizontally.

Every edition deploys `standalone` by default; an explicit `--deployment-mode` always wins. An
existing install keeps its current topology on `--update` unless `--deployment-mode` is passed.

You can switch topology on an existing install with `--update true --deployment-mode <mode>`:
MySQL/OpenSearch/Document Server are reused as-is (no data loss), only the app layer is replaced.
Not all Docker-specific flags apply in `standalone` mode (e.g. `--installrabbitmq`/`--installredis`
are ignored, since that topology has no separate Redis/RabbitMQ containers).

#### Document Server (ONLYOFFICE Docs)
| Flag                    | Value placeholder           | Default value                  | Description                             |
|-------------------------|-----------------------------|--------------------------------|-----------------------------------------|
| `--installdocs`         | `true` \| `false`           | `true`                         | Install / update Document Server        |
| `--docsimage`           | `<IMAGE_NAME>`              | `onlyoffice/documentserver-ee` | Document Server image name              |
| `--docsversion`         | `<VERSION>`                 | *(latest stable)*              | Document Server version                 |
| `--docsurl`             | `<URL>`                     | -                              | URL of external Docs instance           |

#### MySQL
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--installmysql`        | `true` \| `false`           | `true`               | Deploy MySQL container       |
| `--mysqlrootpassword`   | `<PASS>`                    | *(auto-generated)*   | Root password                |
| `--mysqldatabase`       | `<DB_NAME>`                 | onlyoffice_apps      | ONLYOFFICE Apps DB name             |
| `--mysqluser`           | `<USER>`                    | -                    | DB user                      |
| `--mysqlpassword`       | `<PASS>`                    | *(auto-generated)*   | DB user password             |
| `--mysqlhost`           | `<HOST>`                    | `localhost`          | Host/IP                      |
| `--mysqlport`           | `<PORT>`                    | `3306`               | MySQL port                   |

#### RabbitMQ
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--installrabbitmq`     | `true` \| `false`           | `true`               | Deploy RabbitMQ              |
| `--rabbitmqprotocol`    | `<PROTO>`                   | `amqp`               | Protocol                     |
| `--rabbitmqhost`        | `<HOST>`                    | `localhost`          | Host/IP                      |
| `--rabbitmqport`        | `<PORT>`                    | `5672`               | Port                         |
| `--rabbitmqusername`    | `<USER>`                    | -                    | Username                     |
| `--rabbitmqpassword`    | `<PASS>`                    | -                    | Password                     |
| `--rabbitmqvirtualhost` | `<VHOST>`                   | `/`                  | Virtual host                 |

#### Redis
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--installredis`        | `true` \| `false`           | `true`               | Deploy Redis                 |
| `--redishost`           | `<HOST>`                    | `localhost`          | Host/IP                      |
| `--redisport`           | `<PORT>`                    | `6379`               | Port                         |
| `--redisusername`       | `<USER>`                    | -                    | Username (optional)          |
| `--redispassword`       | `<PASS>`                    | -                    | Password (optional)          |

#### OpenSearch
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--installelastic`      | `true` \| `false`           | `true`               | Deploy OpenSearch            |
| `--elasticprotocol`     | `<PROTO>`                   | `http`               | Protocol                     |
| `--elastichost`         | `<HOST>`                    | `localhost`          | Host/IP                      |
| `--elasticport`         | `<PORT>`                    | `9200`               | Port                         |

#### OpenSearch Dashboards
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--dashboardsusername`  | `<USER>`                    | `onlyoffice`         | Dashboards login             |
| `--dashboardspassword`  | `<PASS>`                    | *(auto-generated)*   | Dashboards password          |

#### Fluent Bit
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--installfluentbit`    | `true` \| `false`           | `true`               | Deploy Fluent Bit for logs   |

#### SSL / HTTPS & Let's Encrypt
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--letsencryptdomain`   | `<DOMAIN>`                  | -                    | Domain for Let's Encrypt     |
| `--letsencryptmail`     | `<MAIL>`                    | -                    | Admin email                  |
| `--certfile`            | `<FILE>`                    | -                    | Path to existing certificate |
| `--certkeyfile`         | `<FILE>`                    | -                    | Path to existing key         |

#### Misc
| Flag                    | Value placeholder           | Default value        | Description                  |
|-------------------------|-----------------------------|----------------------|------------------------------|
| `--noninteractive`      | `true` \| `false`           | `false`              | Auto-confirm prompts         |


## 💡 Examples

Typical usage scenarios with different combinations of flags.  

1. Quick install on port 8080
```bash
sudo bash apps-install.sh docker --externalport 8080
```

2. Update all components, skip hardware check
```bash
sudo bash apps-install.sh \
  --update true \
  --skiphardwarecheck true
```

3. Install ONLYOFFICE Apps without ONLYOFFICE Docs
```bash
sudo bash apps-install.sh --installdocs false
```

4. Update ONLYOFFICE Docs only to version 9.0.2
```bash
sudo bash apps-install.sh \
  --update true \
  --docsimage onlyoffice/documentserver-ee \
  --docsversion 9.0.2 \
  --installdocs true \
  --installapps false \
  --installrabbitmq false \
  --installredis false
```

5. Update ONLYOFFICE Apps to a specific version 4.0.0 and skip all other components
```bash
sudo bash apps-install.sh \
  --update true \
  --appsversion 4.0.0 \
  --installdocs false \
  --installrabbitmq false \
  --installredis false
```

6. Pull images from a private registry
```bash
sudo bash apps-install.sh \
  --registry https://reg.example.com:5000 \
  --username USER \
  --password PASS
```

7. Set JWT header & secret
```bash
sudo bash apps-install.sh \
  --jwtheader Authorization \
  --jwtsecret super-secret-key
```

8. Custom MySQL root password
```bash
sudo bash apps-install.sh --mysqlrootpassword new-secret-pw
```

9. Automatic Let's Encrypt
```bash
sudo bash apps-install.sh \
  --letsencryptdomain yourdomain.com \
  --letsencryptmail admin@yourdomain.com
```

10. Bring your own certificate
```bash
sudo bash apps-install.sh \
  --certfile /path/fullchain.pem \
  --certkeyfile /path/privkey.pem
```

11. Connect external ONLYOFFICE Docs
```bash
sudo bash apps-install.sh \
  --installdocs false \
  --docsurl http://docs.example.com:8080
```

12. Use external MySQL
```bash
sudo bash apps-install.sh \
  --installmysql false \
  --mysqlhost mysql.example.com \
  --mysqlport 3306 \
  --mysqldatabase onlyoffice_apps \
  --mysqluser apps \
  --mysqlpassword super-secret
```

13. Use external RabbitMQ
```bash
sudo bash apps-install.sh \
  --installrabbitmq false \
  --rabbitmqprotocol amqp \
  --rabbitmqhost mq.example.com \
  --rabbitmqport 5672 \
  --rabbitmqusername apps \
  --rabbitmqpassword mq-pass \
  --rabbitmqvirtualhost /
```

14. Use external Redis
```bash
sudo bash apps-install.sh \
  --installredis false \
  --redishost redis.example.com \
  --redisport 6379 \
  --redispassword redis-pass
```

15. Use external OpenSearch
```bash
sudo bash apps-install.sh \
  --installelastic false \
  --elasticprotocol https \
  --elastichost search.example.com \
  --elasticport 9200
```
16. Combined example: all external services, update only ONLYOFFICE Apps
```bash
sudo bash apps-install.sh \
  --update true \
  --installapps true \
  --appsversion 4.0.0 \
  --installdocs false \
  --installmysql false \
  --installrabbitmq false \
  --installredis false \
  --installelastic false \
  --docsurl https://docs.example.com \
  --mysqlhost mysql.example.com \
  --mysqluser apps \
  --mysqlpassword super-secret \
  --rabbitmqhost mq.example.com \
  --rabbitmqusername apps \
  --rabbitmqpassword mq-pass \
  --redishost redis.example.com \
  --redispassword redis-pass \
  --elastichost search.example.com \
  --elasticprotocol https
```

17. Install the single-container standalone stack, then switch to the microservices topology
    (MySQL/OpenSearch/Document Server data is preserved)
```bash
sudo bash apps-install.sh docker --deployment-mode standalone

sudo bash apps-install.sh docker \
  --update true \
  --deployment-mode microservices
```

## 🔄 Installing over ONLYOFFICE Docs and rolling back

If standalone ONLYOFFICE Docs is already installed, the installer reuses it instead of deploying a second Document Server.

### Packages (DEB/RPM)

Docs (`onlyoffice-documentserver`, `-de` or `-ee`) is detected automatically. Before changing anything, the installer saves a snapshot of its nginx configuration, Let's Encrypt renewal settings and `Data` permissions. Then:

- If Docs uses a port required by Apps, it is moved to another one (`8083` by default).
- If Docs serves HTTPS with a valid certificate, Apps takes it over and Docs switches to plain HTTP on `127.0.0.1:8083`.
- If the installation fails, Docs is restored automatically; re-run the installer to finish.

**Rolling back to standalone Docs:**

```bash
sudo bash apps-install.sh package --uninstall true
```

Answer "N" to "Also uninstall ONLYOFFICE Docs?" to keep Docs: the snapshot is restored before the Apps packages are removed. After a clean installation without a snapshot, a standard Docs HTTP configuration is made accessible on its existing port (`8083` by default); HTTPS configured in Apps is not transferred to Docs. If the configuration cannot be restored or is unsupported, the script stops before removing any packages.

### Docker

For Docs installed with `docker run`, the installer keeps the original container stopped with automatic restart disabled. Apps uses a copy of its main data. Run this command to restore Docs and keep Apps data and settings for reinstallation:

```bash
sudo bash apps-install.sh docker --uninstall true
```

Keep the original container, its data and the `/app/onlyoffice/.docs-restore` directory. `docker container prune` deletes the saved container. Additional custom mounts remain shared with Apps. Automatic restoration requires the installer to have saved the original container. Older installations need a backup or VM snapshot. Fresh Apps installations keep the usual uninstall options.

## 🖥 System Requirements

| Resource   | Minimum              |
|------------|----------------------|
| **CPU**    | 4-core               |
| **RAM**    | 8 GB                 |
| **Disk**   | 40 GB+ free          |
| **Swap**   | ≥ 6 GB               |
| **Kernel** | Linux 3.10+ (x86_64) |

\* Minimum requirements for test environments. For production, 8 GB RAM or more is recommended.

## ✅ Supported Operating Systems

The installation scripts support the following operating systems, which are **regularly tested** as part of our CI/CD pipelines:

<!-- OS-SUPPORT-LIST-START -->
- RHEL 9
- CentOS 9S
- CentOS 10S
- Fedora 43
- Fedora 44
- Debian 11 (x86_64, ARM64)
- Debian 12 (x86_64, ARM64)
- Debian 13 (x86_64, ARM64)
- Ubuntu 22.04 (x86_64, ARM64)
- Ubuntu 24.04 (x86_64, ARM64)
- Ubuntu 26.04 (x86_64, ARM64)
<!-- OS-SUPPORT-LIST-END -->

## 🍎 macOS

Apps can be installed in Docker on macOS (Apple Silicon and Intel) with [Docker Desktop](https://docs.docker.com/desktop/setup/install/mac-install/). The DEB/RPM installation is not available.

- Run the script **without** `sudo`: Docker Desktop works per user.
- [Homebrew](https://brew.sh) is required. The script installs `bash`, `coreutils`, `findutils`, `gnu-sed`, `grep`, `gnu-tar` and `jq` with it and re-runs itself under the Homebrew `bash`.
- Docker Desktop is installed with Homebrew when it is missing (accept its license agreement in the window that opens) and started automatically when it is not running. CPU and memory are taken from its limits (Settings > Resources): at least 4 cores and 8 GB RAM.
- Configuration files are stored in `~/onlyoffice` by default. Use `--basedir <DIR>` to change it; the path must be shared with Docker Desktop.
- Data is kept in Docker volumes by default. With `--volumesdir <DIR>` it is kept in the directory instead: the owner of its subdirectories is set from a helper container, because on the Mac a user cannot give files to another owner; the directory must be shared with Docker Desktop.
- HTTPS works only in the standalone deployment mode, with your own certificate (`--certfile`, `--certkeyfile`, `--certdomain`) or with Let's Encrypt (`--letsencryptdomain`, `--letsencryptmail`). For Let's Encrypt the domain must point to the Mac and ports 80 and 443 must be reachable from the Internet. The certificate is renewed weekly (Sunday, 03:00) by the launchd agent `~/Library/LaunchAgents/com.onlyoffice.apps-renew-letsencrypt.plist`, which needs the Mac awake and Docker Desktop running.
- An existing Document Server container started with `docker run` is adopted like on Linux; its data is copied between Docker volumes by a helper container.

```bash
bash apps-install.sh docker
```

## 📚 Additional Resources

| Resource         | Link                                                                 |
|------------------|----------------------------------------------------------------------|
| Official website | <https://www.onlyoffice.com/>                                        |
| Docs installer   | <https://github.com/ONLYOFFICE/OneClickInstall-Docs>                 |
| Help Center      | <https://helpcenter.onlyoffice.com/docspace/installation>            |
| Product page     | <https://www.onlyoffice.com/docspace.aspx>                           |
| Community Forum  | <https://community.onlyoffice.com>                                   |
| Stack Overflow   | <https://stackoverflow.com/questions/tagged/onlyoffice>              |

## 📝 License

ONLYOFFICE Apps is distributed under the [**GNU AGPL v3**](https://docspace.onlyoffice.com/s/wjQ94v2GWfm65wH) license for the Community Edition.  
**Enterprise** and **Developer** editions require a valid commercial license. For more details, please contact [sales@onlyoffice.com](mailto:sales@onlyoffice.com).

