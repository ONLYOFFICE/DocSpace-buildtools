[![License](https://img.shields.io/badge/License-GNU%20AGPL%20V3-green.svg?style=flat)](https://www.gnu.org/licenses/agpl-3.0.en.html)
[![Docker Pulls](https://img.shields.io/docker/pulls/onlyoffice/docspace-files?logo=docker)](https://hub.docker.com/r/onlyoffice/docspace-files)
[![Docker Image Version](https://img.shields.io/docker/v/onlyoffice/docspace-files?sort=semver&logo=docker)](https://hub.docker.com/r/onlyoffice/docspace-files/tags)
[![GitHub Stars](https://img.shields.io/github/stars/ONLYOFFICE/DocSpace-buildtools?style=flat&logo=github)](https://github.com/ONLYOFFICE/DocSpace-buildtools/stargazers)

# ONLYOFFICE DocSpace - OneClickInstall

A simple self-hosted installer for **ONLYOFFICE DocSpace** using Docker or Linux packages.

| 🚀 [Start](#-quick-start) | 🛠 [Flags](#-flags) | 💡 [Examples](#-examples) | 🖥️ [Reqs](#-system-requirements) | ✅ [OS](#-supported-operating-systems) | 📚 [Resources](#-additional-resources) | 📝 [License](#-license) |
|--------------------------|--------------------------------------------|---------------------------|----------------------------------------|----------------------------------------|----------------------------------------|----------------------|

**ONLYOFFICE DocSpace** is a room-based collaborative platform which allows organizing a clear file structure depending on users' needs or project goals. Flexible access  permissions and user roles allow fine-tuning the access to the whole space or separate rooms.

## 🚀 Quick Start

### 1. Download the installer

Community Edition (default):

```bash
curl -O https://download.onlyoffice.com/docspace/docspace-install.sh
```

If you want to install a different edition, choose one of the following:

> **Enterprise Edition:**
> ```bash
> curl -O https://download.onlyoffice.com/docspace/docspace-enterprise-install.sh
> ```

> **Developer Edition:**
> ```bash
> curl -O https://download.onlyoffice.com/docspace/docspace-developer-install.sh
> ```

### 2. Run the script
Use the downloaded script to install ONLYOFFICE DocSpace with either the RPM/DEB package or Docker.  

**Install as RPM/DEB Package**:
```bash
sudo bash <script-name> package
```

**Install via Docker**:
```bash
sudo bash <script-name> docker
```

Replace `<script-name>` with the name of the downloaded script (e.g., `docspace-enterprise-install.sh`).

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

#### DocSpace Core
| Flag                    | Value placeholder                         | Default value             | Description                    |
|-------------------------|-------------------------------------------|---------------------------|--------------------------------|
| `--installdocspace`     | `true` \| `false`                         | `true`                    | Install / update DocSpace      |
| `--docspaceversion`     | `<VERSION>`                               | *(latest stable)*         | DocSpace version               |
| `--docspacehost`        | `<HOST>`                                  | `localhost`               | Hostname / IP                  |
| `--externalport`        | `<PORT>`                                  | `80`                      | External HTTP port             |
| `--machinekey`          | `<KEY>`                                   | *(auto-generated)*        | `core.machinekey` value        |

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
| `--mysqldatabase`       | `<DB_NAME>`                 | onlyoffice           | DocSpace DB name             |
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
sudo bash docspace-install.sh docker --externalport 8080
```

2. Update all components, skip hardware check
```bash
sudo bash docspace-install.sh \
  --update true \
  --skiphardwarecheck true
```

3. Install DocSpace without ONLYOFFICE Docs
```bash
sudo bash docspace-install.sh --installdocs false
```

4. Update ONLYOFFICE Docs only to version 9.0.2
```bash
sudo bash docspace-install.sh \
  --update true \
  --docsimage onlyoffice/documentserver-ee \
  --docsversion 9.0.2 \
  --installdocs true \
  --installdocspace false \
  --installrabbitmq false \
  --installredis false
```

5. Update DocSpace to a specific version 3.2.0 and skip all other components
```bash
sudo bash docspace-install.sh \
  --update true \
  --docspaceversion 3.2.0 \
  --installdocs false \
  --installrabbitmq false \
  --installredis false
```

6. Pull images from a private registry
```bash
sudo bash docspace-install.sh \
  --registry https://reg.example.com:5000 \
  --username USER \
  --password PASS
```

7. Set JWT header & secret
```bash
sudo bash docspace-install.sh \
  --jwtheader Authorization \
  --jwtsecret super-secret-key
```

8. Custom MySQL root password
```bash
sudo bash docspace-install.sh --mysqlrootpassword new-secret-pw
```

9. Automatic Let's Encrypt
```bash
sudo bash docspace-install.sh \
  --letsencryptdomain yourdomain.com \
  --letsencryptmail admin@yourdomain.com
```

10. Bring your own certificate
```bash
sudo bash docspace-install.sh \
  --certfile /path/fullchain.pem \
  --certkeyfile /path/privkey.pem
```

11. Connect external ONLYOFFICE Docs
```bash
sudo bash docspace-install.sh \
  --installdocs false \
  --docsurl http://docs.example.com:8080
```

12. Use external MySQL
```bash
sudo bash docspace-install.sh \
  --installmysql false \
  --mysqlhost mysql.example.com \
  --mysqlport 3306 \
  --mysqldatabase docspace \
  --mysqluser docspace \
  --mysqlpassword super-secret
```

13. Use external RabbitMQ
```bash
sudo bash docspace-install.sh \
  --installrabbitmq false \
  --rabbitmqprotocol amqp \
  --rabbitmqhost mq.example.com \
  --rabbitmqport 5672 \
  --rabbitmqusername docspace \
  --rabbitmqpassword mq-pass \
  --rabbitmqvirtualhost /
```

14. Use external Redis
```bash
sudo bash docspace-install.sh \
  --installredis false \
  --redishost redis.example.com \
  --redisport 6379 \
  --redispassword redis-pass
```

15. Use external OpenSearch
```bash
sudo bash docspace-install.sh \
  --installelastic false \
  --elasticprotocol https \
  --elastichost search.example.com \
  --elasticport 9200
```
16. Combined example: all external services, update only DocSpace
```bash
sudo bash docspace-install.sh \
  --update true \
  --installdocspace true \
  --docspaceversion 3.2.0 \
  --installdocs false \
  --installmysql false \
  --installrabbitmq false \
  --installredis false \
  --installelastic false \
  --docsurl https://docs.example.com \
  --mysqlhost mysql.example.com \
  --mysqluser docspace \
  --mysqlpassword super-secret \
  --rabbitmqhost mq.example.com \
  --rabbitmqusername docspace \
  --rabbitmqpassword mq-pass \
  --redishost redis.example.com \
  --redispassword redis-pass \
  --elastichost search.example.com \
  --elasticprotocol https
```

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
- CentOS 9s
- CentOS 10
- Debian 11
- Debian 12
- Debian 13
- Ubuntu 22.04
- Ubuntu 24.04
- Fedora 42
- Fedora 43
<!-- OS-SUPPORT-LIST-END -->

## 📚 Additional Resources

| Resource         | Link                                                                 |
|------------------|----------------------------------------------------------------------|
| Official website | <https://www.onlyoffice.com/>                                        |
| Docs installer   | <https://github.com/ONLYOFFICE/OneClickInstall-Docs>                 |
| Help Center      | <https://helpcenter.onlyoffice.com/docspace/installation>            |
| Product page     | <https://www.onlyoffice.com/docspace.aspx>                           |
| Community Forum  | <https://forum.onlyoffice.com>                                       |
| Stack Overflow   | <https://stackoverflow.com/questions/tagged/onlyoffice>              |

## 📝 License

ONLYOFFICE DocSpace is distributed under the [**GNU AGPL v3**](https://onlyo.co/38YZGJh) license for the Community Edition.  
**Enterprise** and **Developer** editions require a valid commercial license. For more details, please contact [sales@onlyoffice.com](mailto:sales@onlyoffice.com).

