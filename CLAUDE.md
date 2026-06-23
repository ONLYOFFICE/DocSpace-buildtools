## Project Overview

ONLYOFFICE DocSpace Build Tools — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration for [DocSpace-server](../DocSpace-server) and [DocSpace-client](../DocSpace-client).

## Tech Stack

.NET (C#), Node.js, Java, Python 3, Bash/PowerShell, Docker/BuildX, Nginx, Supervisor, MySQL, Redis, RabbitMQ, OpenSearch

## Common Commands

```bash
# Build
./build.sh                          # Full backend + frontend build (Linux)
./build.backend.sh                  # Backend only
./build.backend.docker.py           # Backend via Docker
./build.static.sh                   # Static assets

# Database migrations
./runMigrations.sh                  # Linux
runMigrations.bat                   # Windows
runMigrations.standalone.bat        # Windows (standalone mode)

# Service lifecycle (dev)
./start/start.sh                    # Start all services
./start/stop.sh                     # Stop all services
./start/restart.sh                  # Restart all services

# Docker Compose (from install/docker/)
docker compose -f docspace.yml -f db.yml -f redis.yml -f rabbitmq.yml up -d
docker compose -f docspace-stack.yml up -d  # Full stack shortcut

# OneClickInstall
bash install/OneClickInstall/docspace-install.sh      # Universal installer
bash install/OneClickInstall/install-Docker.sh        # Docker only
bash install/OneClickInstall/install-Debian.sh        # Debian/Ubuntu
bash install/OneClickInstall/install-RedHat.sh        # RHEL/CentOS

# Translation tests
./run.translations.tests.py
./run.backend.translations.tests.sh
```

## Project Structure

```
config/                     — Application configuration (41 JSON + nginx)
  appsettings*.json         — App configs (base, developer, enterprise, test, services)
  autofac*.json             — DI container (base, consumers, products)
  storage.json              — Storage backend
  externalresources*.json   — CDN/external URLs (base, developer, enterprise)
  redis.json / rabbitmq.json / elastic.json / socket.json / notify.json
  nlog.config               — Structured logging (NLog)
  dnsmasq.conf              — DNS for local dev
  radicale.*                — CalDAV/CardDAV server configs
  nginx/                    — Nginx configs + templates + docker-entrypoint.d/
  document-formats/         — Document format definitions (git submodule)
  supervisor/               — Supervisor configs (dotnet_services, node_services, java_services)

install/
  docker/                   — Dockerfiles, Compose files, entrypoints
    Dockerfile.app          — Main multi-stage DocSpace image
    Dockerfile.runtime      — Runtime dependencies
    Dockerfile.ffvideo       — FFmpeg video processing
    docker-entrypoint.py/sh — Main service entrypoints
    docker-identity-entrypoint.sh
    docker-migration-entrypoint.sh
    docker-healthchecks-entrypoint.sh
    bin-share-docker-entrypoint.sh / wait-bin-share-docker-entrypoint.sh
    build.hcl               — BuildX multi-arch config
    build.yml / build-identity.yml
    docspace.yml            — All DocSpace app services
    docspace-stack.yml      — Full stack (app + all dependencies)
    docspace.profiles.yml   — Profile-based configs
    docspace.overcome.yml   — Local dev overrides
    db.yml / db.dev.yml     — MySQL
    redis.yml               — Redis
    rabbitmq.yml            — RabbitMQ
    opensearch.yml          — OpenSearch
    identity.yml            — OAuth2 identity service
    proxy.yml / proxy-ssl.yml — Nginx reverse proxy
    ds.yml                  — ONLYOFFICE Document Server
    migration-runner.yml    — DB migration runner container
    fluent.yml              — Fluent Bit log collector
    healthchecks.yml        — Health check UI
    notify.yml              — Notification service
    dnsmasq.yml             — DNS for local dev
  OneClickInstall/          — Installer scripts (Debian, RedHat, Docker, universal)
  common/                   — Shared packaging: build-services.py/sh, changelog.sh,
                              packages-build.sh, plugins-build.sh, systemd/, product-ssl-setup/
  win/                      — Windows installer (Advanced Installer .aip, WinSW, Nginx, OpenSearch)
  deb/                      — Debian package metadata
  rpm/                      — RPM spec files
  snap/                     — Snap package config

run/                        — Per-service launch scripts (28 services, .bat + .xml)
                              WebApi, Files, People, Notify, Backup, AI, Identity, etc.
scripts/                    — Service startup: identity, socketio, ssoauth, webdav (.sh + .bat)
start/                      — Dev lifecycle: start/stop/restart (.sh + .bat + .py)
tests/                      — lint/, vagrant/
tools/                      — check.sh
templates/                  — gitea-claude-review (AI code review templates)
.github/workflows/          — 18 GitHub Actions workflows (see CI/CD section)
Jenkinsfile                 — Jenkins declarative pipeline
```

## Docker Compose Architecture

Compose is **modular** — compose files are combined with `-f`. The `install/docker/.env` has ~200 variables covering all services.

Key compose combinations:
```bash
# Minimal (app only, external deps assumed)
docker compose -f docspace.yml up -d

# Full local stack
docker compose -f docspace-stack.yml up -d

# With local dev overrides
docker compose -f docspace.yml -f docspace.overcome.yml up -d
```

## CI/CD Workflows

**Build & Release** (`.github/workflows/`):

| Workflow | Purpose |
|----------|---------|
| `main-build.yml` | Multi-arch Docker build (dotnet + node + java) |
| `build_packages.yml` | DEB/RPM packages |
| `config-build.yml` | Config-triggered builds |
| `cron-build.yml` | Nightly scheduled builds |
| `windows-build.yml` | Windows installer |
| `release-docspace.yaml` | Production release |
| `offline-release.yml` | Offline package build |
| `oci-release.yml` | Container registry release |

**Testing & Quality:**

| Workflow | Purpose |
|----------|---------|
| `ci-oci-docker-install.yml` | OneClickInstall Docker tests |
| `ci-oci-install.yml` | Linux package install tests |
| `ci-oci-update.yml` | Update mechanism tests |
| `zap-scanner.yaml` | OWASP ZAP security scan |
| `claude-auto-review.yml` | Automated PR review with Claude |

## Key Patterns

- Docker Compose is modular: each infra component has its own `.yml`, combined with `-f`
- All config via `.env` in `install/docker/` (~200 vars) and JSON in `config/`
- Three editions: Community, Enterprise, Developer (toggled via env vars and appsettings overrides)
- `run/` contains per-service launchers; `start/` orchestrates all services together
- Windows services managed with WinSW (`run/*.xml`); Linux with Supervisor or systemd

## Review Focus

**Security**: Hardcoded credentials, injection vulnerabilities, insecure defaults in `.env` and configs
**Docker**: Entrypoint scripts, multi-stage builds, image size, privilege escalation
**Shell/Python**: `set -e`, quoting, error handling in install scripts
**Config**: Sensitive data, default passwords, exposed ports in JSON configs
**CI/CD**: Secret handling, pinned versions, permissions in workflows
**Nginx**: Routing rules in `config/nginx/onlyoffice.conf`, proxy configs

## Git Workflow

- **Main branch**: `master`
- **Integration branch**: `develop`
- **Branch naming**: `feature/*`, `bugfix/*`, `hotfix/*`, `release/*`
