# ONLYOFFICE DocSpace Build Tools

[![Release Notes](https://img.shields.io/github/release/ONLYOFFICE/DocSpace?style=flat-square)](https://github.com/ONLYOFFICE/DocSpace/releases)
[![License](https://img.shields.io/badge/license-AGPLv3-orange)](https://opensource.org/license/agpl-v3)
[![GitHub stars](https://img.shields.io/github/stars/ONLYOFFICE/DocSpace?style=flat-square)](https://star-history.com/#ONLYOFFICE/DocSpace)
[![Open Issues](https://img.shields.io/github/issues-raw/ONLYOFFICE/DocSpace?style=flat-square)](https://github.com/ONLYOFFICE/DocSpace/issues)

This repository contains the **build, deployment, and infrastructure** tooling for [ONLYOFFICE DocSpace](https://github.com/ONLYOFFICE/DocSpace) — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration.

> For the full product overview, see the [main repository README](https://github.com/ONLYOFFICE/DocSpace#readme).
> For backend development, see the [server README](https://github.com/ONLYOFFICE/DocSpace-server#readme).
> For frontend development, see the [client README](https://github.com/ONLYOFFICE/DocSpace-client#readme).

## Table of Contents

- [Project Structure](#project-structure)
- [Installation](#installation)
  - [Universal Installer](#universal-installer)
  - [Docker](#docker-install)
  - [Linux Packages](#linux-packages)
  - [Windows Installer](#windows-installer)
- [Docker](#docker)
  - [Dockerfiles](#dockerfiles)
  - [Docker Compose Services](#docker-compose-services)
  - [Environment Variables](#environment-variables)
- [Configuration](#configuration)
  - [Application Settings](#application-settings)
  - [Nginx](#nginx)
  - [Database](#database)
  - [Process Management](#process-management)
- [Database Migrations](#database-migrations)
- [CI/CD](#cicd)
  - [GitHub Actions](#github-actions)
  - [Jenkins](#jenkins)
- [Licensing](#licensing)

## Project Structure

```
buildtools/
├── config/                     # Application configuration
│   ├── appsettings*.json      # App configs (various profiles)
│   ├── autofac*.json          # Dependency injection configs
│   ├── storage.json           # Storage backend config
│   ├── externalresources.json # CDN and external URLs
│   ├── nginx/                 # Web server configuration
│   │   ├── onlyoffice.conf
│   │   ├── includes/
│   │   └── templates/
│   ├── mysql/                 # Database configuration
│   ├── supervisor/            # Process management
│   ├── document-formats/      # Document format definitions (submodule)
│   └── *.json                 # Service-specific configs (redis, rabbitmq, etc.)
├── install/                    # Installation infrastructure
│   ├── OneClickInstall/       # Docker and package installers
│   ├── docker/                # Dockerfiles, Compose files, entrypoints
│   ├── common/                # Shared build and packaging scripts
│   ├── win/                   # Windows Advanced Installer projects
│   ├── deb/                   # Debian package metadata
│   ├── rpm/                   # RPM package metadata
│   └── snap/                  # Snap package configuration
├── run/                        # Per-service executables (28 services, .bat)
├── scripts/                    # Service startup scripts (identity, socketio, sso, webdav)
├── start/                      # Service lifecycle (start.sh, stop.sh, restart.sh)
├── tests/                      # Test utilities (lint, vagrant)
├── tools/                      # Utility scripts
├── .github/workflows/          # GitHub Actions (18 workflows)
├── build*.sh, build*.bat       # Platform-specific build scripts
├── run*.sh, run*.bat           # Test and migration runners
├── *.py                        # Python orchestration utilities
└── Jenkinsfile                 # Jenkins pipeline
```

## Installation

### OneClickInstall

The primary deployment method. Located in `install/OneClickInstall/`.

<a id="universal-installer"></a>
**Universal installer:**
```bash
# Quick install
bash install/OneClickInstall/docspace-install.sh
```

<a id="docker-install"></a>
**Docker:**
```bash
bash install/OneClickInstall/install-Docker.sh
```

<a id="linux-packages"></a>
**Linux Packages:**
```bash
# Debian/Ubuntu
bash install/OneClickInstall/install-Debian.sh

# RHEL/CentOS/Fedora
bash install/OneClickInstall/install-RedHat.sh
```

Package metadata is maintained in `install/deb/` and `install/rpm/`.

All installers support extensive flags for customization (see [OneClickInstall README](install/OneClickInstall/README.md)).

### Windows Installer

Windows installation uses Advanced Installer projects (`.aip` files) located in `install/win/`, with WinSW for service management.

See the [Windows installation guide](https://guides.onlyoffice.com/installation/docspace-community-install-windows.aspx) for detailed instructions.

## Docker

### Dockerfiles

Located in `install/docker/`:

| Dockerfile | Purpose |
|-----------|---------|
| `Dockerfile.app` | Main multi-stage build for DocSpace |
| `Dockerfile.runtime` | Runtime dependencies image |

Multi-platform builds are supported via `build.hcl` (Docker Buildx).

### Docker Compose Services

Located in `install/docker/`, the Compose setup is modular — each infrastructure component has its own file:

| File | Services |
|------|----------|
| `docspace.yml` | All DocSpace application services |
| `docspace-stack.yml` | Full stack with all dependencies |
| `docspace.profiles.yml` | Profile-based service configurations |
| `docspace.overcome.yml` | Overrides for local development |
| `db.yml` / `db.dev.yml` | MySQL database |
| `redis.yml` | Redis cache |
| `rabbitmq.yml` | RabbitMQ message broker |
| `opensearch.yml` | OpenSearch engine |
| `identity.yml` | OAuth2 identity service |
| `proxy.yml` / `proxy-ssl.yml` | Nginx reverse proxy (with/without SSL) |
| `ds.yml` | ONLYOFFICE Document Server |
| `migration-runner.yml` | Database migration runner |
| `fluent.yml` | Fluent Bit log collector |
| `dashboards.yml` | OpenSearch dashboards |
| `healthchecks.yml` | Health check monitoring |
| `notify.yml` | Notification services |
| `dnsmasq.yml` | DNS resolution for local development |

### Environment Variables

The `.env` file in `install/docker/` contains ~200 configuration variables covering all services. Key categories:

- Service ports and endpoints
- Database credentials
- Redis and RabbitMQ connections
- OpenSearch settings
- Document Server integration
- SSL/TLS configuration
- Edition selection (Community/Enterprise/Developer)

## Configuration

### Application Settings

41 JSON configuration files in `config/`:

| File | Purpose |
|------|---------|
| `appsettings.json` | Main application configuration |
| `appsettings.developer.json` | Developer edition overrides |
| `appsettings.enterprise.json` | Enterprise edition overrides |
| `appsettings.services.json` | Service-specific settings |
| `appsettings.test.json` | Test environment settings |
| `autofac.json` | DI container configuration |
| `autofac.consumers.json` | Consumer service DI bindings |
| `autofac.products.json` | Product module DI bindings |
| `storage.json` | Storage backend configuration |
| `externalresources.json` | CDN and external resource URLs |
| `redis.json` | Redis connection settings |
| `rabbitmq.json` | RabbitMQ connection settings |
| `elastic.json` | OpenSearch settings |
| `socket.json` | Socket.IO settings |
| `nlog.config` | Structured logging configuration |

### Nginx

Two separate nginx roles, each with its own config directory.

**Application router** (`config/nginx/`) — OpenResty-based, baked into the router Docker image:
- `onlyoffice.conf` — Main routing config: location blocks for all services (API, login, doceditor, management, sdk, socket.io, ds-vpath, etc.)
- `onlyoffice-client.conf` / `onlyoffice-login.conf` / `onlyoffice-management.conf` — Per-service nginx configs
- `proxy-frontend.conf` / `proxy-frontend-virt.conf` — Frontend proxying rules
- `includes/onlyoffice-upstream-map.conf.template` — Service URL maps (processed by envsubst at container start)
- `includes/onlyoffice-public.conf` — Public-facing location rules
- `includes/server-dashboards.conf` / `server-static-headers.conf` — Reusable include fragments
- `html/custom_4xx.html` / `custom_50x.html` — Custom error pages

**Router Docker image init** (`install/docker/config/nginx/router/`) — copied into the router image at build time:
- `docker-entrypoint.sh` — Entrypoint that runs `docker-entrypoint.d/` scripts then starts nginx
- `docker-entrypoint.d/10-listen-on-ipv6-by-default.sh` — Enables IPv6 listening
- `docker-entrypoint.d/15-local-resolvers.envsh` — Sets `$NGINX_LOCAL_RESOLVERS` from `/etc/resolv.conf`
- `docker-entrypoint.d/20-envsubst-on-templates.sh` — Processes `*.template` files with `envsubst`
- `docker-entrypoint.d/30-tune-worker-processes.sh` — Auto-tunes worker processes
- `templates/upstream.conf.template` — Static upstream definitions
- `templates/onlyoffice-upstream-map.conf.template` — Dynamic service URL maps (reads `SERVICE_*` env vars)

**Proxy** (`install/docker/config/nginx/proxy/`) — mounted into the proxy container at runtime via `proxy.yml`:
- `onlyoffice-proxy.conf` — HTTP reverse proxy: forwards all traffic to the router on port 8092
- `onlyoffice-proxy-ssl.conf` — HTTPS variant with TLS termination, QUIC/HTTP3, HSTS
- `letsencrypt.conf` — ACME challenge location for Let's Encrypt certificate renewal
- `templates/proxy.upstream.conf.template` — upstream server address template

**Shared** (`install/docker/config/nginx/`):
- `nginx.conf.template` — base nginx.conf used by both the proxy and router containers

### Database

- `config/mysql/conf.d/mysql.cnf` — MySQL server tuning

### Process Management

Supervisor configurations in `config/supervisor/`:

| File | Purpose |
|------|---------|
| `supervisord.conf` | Supervisor daemon settings |
| `dotnet_services.conf` | .NET service management |
| `node_services.conf` | Node.js service management |
| `java_services.conf` | Java service management |

## Database Migrations

```bash
# Linux/macOS
./runMigrations.sh

# Windows
runMigrations.bat

# Windows (standalone mode)
runMigrations.standalone.bat
```

Docker-based migrations are handled by `migration-runner.yml` Compose service.

## CI/CD

### GitHub Actions

18 workflows in `.github/workflows/`:

**Build & Release:**

| Workflow | Purpose |
|----------|---------|
| `main-build.yml` | Multi-arch Docker build (dotnet, node, java) |
| `build_packages.yml` | DEB/RPM package building |
| `config-build.yml` | Configuration-triggered builds |
| `cron-build.yml` | Scheduled nightly builds |
| `windows-build.yml` | Windows installer build |
| `release-docspace.yaml` | Production release automation |
| `offline-release.yml` | Offline package building |
| `oci-release.yml` | Container registry release |

**Testing & Quality:**

| Workflow | Purpose |
|----------|---------|
| `ci-oci-docker-install.yml` | OneClickInstall Docker testing |
| `ci-oci-install.yml` | Linux package installation testing |
| `ci-oci-update.yml` | Update mechanism testing |
| `zap-scanner.yaml` | OWASP ZAP security scanning |
| `check-comments.yml` | Code review automation |
| `claude-auto-review.yml` | Automated PR code review with Claude |

**Infrastructure:**

| Workflow | Purpose |
|----------|---------|
| `rebuild-boxes.yml` | VM box rebuilding |
| `readme-update.yml` | Documentation automation |

### Jenkins

`Jenkinsfile` defines a declarative pipeline with:
- Parallel Unix/Windows build stages
- Automated testing
- Telegram notifications

## Licensing

ONLYOFFICE DocSpace is released under AGPLv3 license. See the LICENSE file for more information.

## Need help for developers? 

Check our [official API documentation](https://api.onlyoffice.com/docspace/).