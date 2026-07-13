## Project Overview

ONLYOFFICE DocSpace Build Tools — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration for [DocSpace-server](../DocSpace-server) and [DocSpace-client](../DocSpace-client).

## Tech Stack

.NET (C#), Node.js, Java, Python 3, Bash/PowerShell, Docker/BuildX, Nginx, Supervisor, MySQL, Redis, RabbitMQ, OpenSearch

## Common Commands

```bash
# Build
./scripts/build/build.sh                          # Full backend + frontend build (Linux)
./scripts/build/build.backend.sh                   # Backend only
./scripts/build/build.backend.docker.py            # Backend via Docker
./scripts/build/build.static.sh                    # Static assets

# Database migrations
./scripts/migrations/runMigrations.sh               # Linux
scripts\migrations\runMigrations.bat                # Windows
scripts\migrations\runMigrations.standalone.bat      # Windows (standalone mode)

# Service lifecycle (dev)
./scripts/start/start.sh                    # Start all services
./scripts/start/stop.sh                     # Stop all services
./scripts/start/restart.sh                  # Restart all services

# Docker Compose (from install/docker/)
docker compose -f docspace.yml -f db.yml -f redis.yml -f rabbitmq.yml up -d
docker compose -f docspace-stack.yml up -d  # Full stack shortcut

# OneClickInstall
bash install/OneClickInstall/docspace-install.sh      # Universal installer
bash install/OneClickInstall/install-Docker.sh        # Docker only
bash install/OneClickInstall/install-Debian.sh        # Debian/Ubuntu
bash install/OneClickInstall/install-RedHat.sh        # RHEL/CentOS

# Translation tests
./scripts/test/run.translations.tests.py
./scripts/test/run.backend.translations.tests.sh
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
  nginx/                    — Nginx configs + templates + docker-entrypoint.d/
  document-formats/         — Document format definitions (git submodule)

install/
  docker/                   — Production Compose files (shipped in OCI tarballs)
    build/                  — Build + local-dev assets (NOT shipped to end users):
      Dockerfile            — Main multi-stage DocSpace image
      Dockerfile.runtime    — Runtime dependencies
      Dockerfile.ffvideo    — FFmpeg video processing
      build.hcl             — BuildX multi-arch config
      build.yml
      .dockerignore
      entrypoints/          — Scripts COPY'd into images at build time:
        docker-entrypoint.py
        docker-identity-entrypoint.sh
        docker-migration-entrypoint.sh
        docker-healthchecks-entrypoint.sh
        bin-share-docker-entrypoint.sh / wait-bin-share-docker-entrypoint.sh
        prepare-nginx-router.sh
      dev/                  — Local-dev-only Compose overlays (build.backend.docker.py):
        db.dev.yml            — MySQL dev overrides (exposed ports)
        docspace.profiles.yml — Profile-based configs (local dev)
        docspace.overcome.yml — Local dev overrides
        dnsmasq.yml           — DNS for local dev
        build-identity.yml    — ASC.Identity (Java) build
      stack/supervisor/     — Supervisor service configs baked into the image
    community/              — Single-container community edition stack
    docspace.yml            — All DocSpace app services
    docspace-stack.yml      — Full stack (app + all dependencies)
    db.yml                  — MySQL
    redis.yml               — Redis
    rabbitmq.yml            — RabbitMQ
    opensearch.yml          — OpenSearch
    identity.yml            — OAuth2 identity service
    ds.yml                  — ONLYOFFICE Document Server
    migration-runner.yml    — DB migration runner container
    fluent.yml              — Fluent Bit log collector
    healthchecks.yml        — Health check UI
    notify.yml              — Notification service
    dashboards.yml          — Monitoring dashboards
  OneClickInstall/          — Installer scripts (Debian, RedHat, Docker, universal)
  common/                   — Shared packaging: build-services.py/sh, changelog.sh,
                              packages-build.sh, plugins-build.sh, systemd/, product-ssl-setup/
  win/                      — Windows installer (Advanced Installer .aip, WinSW, Nginx, OpenSearch)
  deb/                      — Debian package metadata
  rpm/                      — RPM spec files

scripts/                    — All local dev tooling
  run/                      — Per-service launch scripts (28 services)
                              WebApi, Files, People, Notify, Backup, AI, Identity, etc.
    windows/                — .bat + .xml launchers (WinSW for Node/Java services)
    macos/                  — launchd .plist files
  start/                    — Dev lifecycle: start/stop/restart (.sh + .bat + .py)
  build/                    — build.sh/.bat, build.backend.*, buildAndDeploy.*, publish.bat, etc.
    service-build/          — Per-service dependency prep: identity, socketio, ssoauth, webdav (.sh + .bat)
  migrations/               — runMigrations.*, createMigrations.bat
  test/                     — run.e2e.*, run.translations.tests.*, run.backend.translations.tests.*
  dev/                      — campaigns.downloader.py, clear.backend.docker.py, debuginfo.py, run.dnsmasq.py
  runasadmin.bat            — Shared Windows elevation helper
tests/                      — lint/, vagrant/
.github/workflows/          — 14 GitHub Actions workflows (see CI/CD section)
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
docker compose --env-file .env -f docspace.yml -f build/dev/docspace.overcome.yml up -d
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
| `readme-update.yml` | Update OS-SUPPORT-LIST |

**Testing & Quality:**

| Workflow | Purpose |
|----------|---------|
| `ci-oci-docker-install.yml` | OneClickInstall Docker tests |
| `ci-oci-install.yml` | Linux package install tests |
| `ci-oci-update.yml` | Update mechanism tests |
| `zap-scanner.yaml` | OWASP ZAP security scan |
| `rebuild-boxes.yml` | Rebuild Vagrant test boxes |

## Key Patterns

- Docker Compose is modular: each infra component has its own `.yml`, combined with `-f`
- All config via `.env` in `install/docker/` (~200 vars) and JSON in `config/`
- Three editions: Community, Enterprise, Developer (toggled via env vars and appsettings overrides)
- `scripts/run/` contains per-service launchers; `scripts/start/` orchestrates all services together
- Windows services managed with WinSW (`scripts/run/windows/*.xml`); Linux with Supervisor or systemd

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
