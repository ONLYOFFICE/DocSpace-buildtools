## Project Overview

ONLYOFFICE Apps Build Tools — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration for [DocSpace-server](../DocSpace-server) and [DocSpace-client](../DocSpace-client).

## Tech Stack

.NET (C#), Node.js, Java, Python 3, Bash/PowerShell, Docker/BuildX, Nginx, Supervisor, MySQL, Redis, RabbitMQ, OpenSearch

## Common Commands

```bash
# Build
./build/build.sh                    # Full backend + frontend build (Linux)
./build/build.backend.sh            # Backend only
./build/build.backend.docker.py     # Backend via Docker
./build/build.static.sh             # Static assets

# Database migrations
./migrations/runMigrations.sh       # Linux
migrations/runMigrations.bat        # Windows
migrations/runMigrations.standalone.bat  # Windows (standalone mode)

# Service lifecycle (dev)
./start/start.sh                    # Start all services
./start/stop.sh                     # Stop all services
./start/restart.sh                  # Restart all services

# Docker Compose (from install/docker/)
# Set MYSQL_ROOT_PASSWORD, MYSQL_PASSWORD, RABBIT_PASSWORD, APP_CORE_MACHINEKEY, IDENTITY_ENCRYPTION_SECRET, and DOCUMENT_SERVER_JWT_SECRET in .env first.
docker compose -f apps.yml -f db.yml -f redis.yml -f rabbitmq.yml up -d
docker compose -f apps-stack.yml up -d  # Full stack shortcut

# OneClickInstall
bash install/OneClickInstall/apps-install.sh          # Universal installer
bash install/OneClickInstall/install-Docker.sh        # Docker only
bash install/OneClickInstall/install-Debian.sh        # Debian/Ubuntu
bash install/OneClickInstall/install-RedHat.sh        # RHEL/CentOS

# Translation tests
./tests/run.translations.tests.py
./tests/run.backend.translations.tests.sh
```

## Project Structure

```
config/                     — Application configuration (~30 JSON + nginx)
  appsettings*.json         — App configs (base, developer, enterprise, test, services)
  autofac*.json             — DI container (base, consumers, products)
  storage.json              — Storage backend
  externalresources*.json   — CDN/external URLs (base, developer, enterprise)
  redis.json / rabbitmq.json / elastic.json / socket.json / notify.json
  nlog.config               — Structured logging (NLog)
  dnsmasq.conf              — DNS for local dev
  nginx/                    — Nginx configs + includes/ + sites-enabled/
  document-formats/         — Document format definitions (git submodule)

install/
  docker/                   — Production Compose files (shipped in OCI tarballs)
    build/                  — Build + local-dev assets (NOT shipped to end users):
      Dockerfile            — Main multi-stage ONLYOFFICE Apps image
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
        docker-standalone-entrypoint.sh
        docker-bin-share-entrypoint.sh / docker-wait-bin-share-entrypoint.sh
        prepare-nginx-router.sh
      dev/                  — Local-dev-only Compose overlays (build/build.backend.docker.py):
        db.dev.yml            — MySQL dev overrides (exposed ports)
        apps.profiles.yml     — Profile-based configs (local dev)
        apps.overcome.yml     — Local dev overrides
        dnsmasq.yml           — DNS for local dev
        build-identity.yml    — ASC.Identity (Java) build
      supervisor/           — Supervisor configs baked into images:
        stack/                — apps-stack.yml services (dotnet/node/java); start-after-migration.py starts
                                ASC.Migration.Runner once MySQL is reachable, then the other services
        standalone.conf       — standalone image
    config/                 — Mounted by the Compose files: apps-ssl-setup, mysql.cnf, fluent-bit.conf, nginx/ (proxy, router)
    standalone/             — Single-container (standalone) stack (own docker-compose.yml + config/apps-ssl-setup)
    apps.yml                — All ONLYOFFICE Apps services
    apps-stack.yml          — Full stack (app + all dependencies)
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
    proxy.yml / proxy-ssl.yml — Standalone Nginx reverse proxy (HTTP / Let's Encrypt SSL)
  OneClickInstall/          — Installer scripts (Debian, RedHat, Docker, universal); install-Docker-docs.sh is sourced
                              by install-Docker.sh (adopting an existing Docs container, rollback, HTTPS handoff)
    common/                 — Shared helpers: logging.sh (loaded by apps-install.sh; OneClick*.log with masked secrets,
                              kept only on failure), check-ports.sh, preserve-docs.sh, swap.sh; a new file here must also be added
                              to the oci-release.yml upload list and the ci-oci-docker-install.yml path filter
  common/                   — Shared packaging: build-services.py/sh, build-linux-package.sh, changelog.sh,
                              packages-build.sh, plugins-build.sh, offline-self-extracting.sh, systemd/,
                              product-configuration, product-ssl-setup (installed as apps-configuration / apps-ssl-setup)
  win/                      — Windows installer, installation in win/README.md, layout and build stages in win/BUILDING.md: build/ (PowerShell:
                              build.ps1 runs the stages and holds the small ones, download.ps1, package.ps1, versions.ps1 the component versions;
                              lib/ helpers incl. configure-files.ps1), installer/ (Apps, Apps.Prerequisites,
                              OpenResty, OpenSearch, OpenSearchStack .aip, utils.ps1 MSI custom actions, Resources/),
                              runtime/ (nginx.conf, sbin/apps-ssl-setup.ps1, winsw/ WinSW binaries + configs), out/ (ignored
                              build output; the .aip paths point at ..\out\)
  deb/                      — Debian package metadata
  rpm/                      — RPM spec files
  install.sh/.bat, uninstall.sh/.bat — Register the dev services from run/ (macOS launchd / Windows sc + WinSW)

run/                        — Per-service dev launchers (~25 services, .bat + WinSW .xml; macos/ launchd .plist)
                              WebApi, Files, People, Notify, Backup, AI, Identity, etc.
scripts/                    — Service startup: aichat, identity, socketio, ssoauth, webdav (.sh + .bat)
start/                      — Dev lifecycle: start/stop/restart (.sh + .bat + .py)
build/                      — Build and deploy scripts: build*.sh/.bat, build.backend.docker.py, buildAndDeploy, publish
migrations/                 — runMigrations*.sh/.bat, createMigrations.bat
tests/                      — arm/ (ARM64 package install), lint/, smoke/, vagrant/ + run.*tests*.{sh,bat,py}, run.e2e.*.bat
tools/                      — runasadmin.bat, debuginfo.py, requirements.txt, run.dnsmasq.py, clear.backend.docker.py, campaigns.downloader.py, check.sh
.github/workflows/          — GitHub Actions workflows (see CI/CD section)
```

## Docker Compose Architecture

Compose is **modular** — compose files are combined with `-f`. The `install/docker/.env` has ~200 variables covering all services.
For direct Compose runs, fill `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `RABBIT_PASSWORD`, `APP_CORE_MACHINEKEY`, `IDENTITY_ENCRYPTION_SECRET`, and `DOCUMENT_SERVER_JWT_SECRET` in `.env` before starting bundled dependencies. `install-Docker.sh` generates these automatically.

Key compose combinations:
```bash
# Minimal (app only, external deps assumed)
docker compose -f apps.yml up -d

# Full local stack
docker compose -f apps-stack.yml up -d

# With local dev overrides
docker compose --env-file .env -f apps.yml -f build/dev/apps.overcome.yml up -d
```

## CI/CD Workflows

**Build & Release** (`.github/workflows/`):

| Workflow | Purpose |
|----------|---------|
| `main-build.yml` | Multi-arch Docker build (dotnet + node + java) |
| `build_packages.yml` | DEB/RPM packages |
| `config-build.yml` | Config-triggered builds |
| `cron-build.yml` | Nightly scheduled builds |
| `release-docker.yaml` | Production release |
| `offline-release.yml` | Offline package build |
| `oci-release.yml` | Container registry release |
| `readme-update.yml` | Update OS support list in README |

**Testing & Quality:**

| Workflow | Purpose |
|----------|---------|
| `ci-oci-docker-install.yml` | OneClickInstall Docker tests: install in stack/microservices/standalone modes, smoke tests, container restart, update from the released version; on macOS the `macOS-script-check` job runs `.github/scripts/macos-check/check.sh` against a fake docker (no VM, no containers) |
| `ci-oci-install.yml` | Linux package install tests |
| `ci-oci-update.yml` | Update mechanism tests |
| `ci-windows-install.yml` | Windows EXE tests of a ready Jenkins `appserver.exe` build (no build in CI) on `windows-2022`: clean install of Prerequisites + edition, checklist (incl. the installer hardening: LocalService services, APPDIR and settings-key ACLs, own DB/broker users on a fresh install, no secrets on sampled command lines) and state scripts in `.github/scripts/windows/`, smoke test (`smoke.ps1` turns known failures into warnings), update from the released Community; secrets `JENKINS_AUTH`, `JENKINS_HOST` (host name only, kept out of the logs), `LICENSE_ENTERPRISE`, `LICENSE_DEVELOPER` (wizard licenses of the editions) |
| `rebuild-boxes.yml` | Rebuild Vagrant boxes for install tests |

## Smoke Tests

`tests/smoke/smoke_test.py` runs against a live portal (`SERVER_URL`); `.github/scripts/docker-utils.sh smoke-test [PYTEST_ARGS]` wraps it for CI.
Tests run in file order and share state. Markers select phases: `bootstrap` (settings, wizard, auth), `seed` (creates data, writes `SMOKE_STATE_FILE`), `verify` (checks the data after a restart or update).
Examples: `-m "bootstrap or seed"` before an update, `-m "bootstrap or verify"` after it. `DEPLOYMENT_MODE` (set by docker-utils.sh) gates mode-specific tests.
`SMOKE_SUMMARY_FILE` receives a result line written by `tests/smoke/conftest.py`. The job summary is published only when the job failed or a section is open (failed tests, audit findings, unhealthy containers).
`docker-utils.sh smoke-test` first waits for the Document Server font generation (it restarts docservice and drops editor sessions) and prints the Document Server container logs when the tests fail; editor tests also wait for Document Server themselves.

## Key Patterns

- Docker Compose is modular: each infra component has its own `.yml`, combined with `-f`
- All config via `.env` in `install/docker/` (~200 vars) and JSON in `config/`
- Three editions: Community, Enterprise, Developer (toggled via env vars and appsettings overrides)
- `run/` contains per-service launchers; `start/` orchestrates all services together
- Windows services: dev via `run/` (WinSW `.xml` + `sc` for `.bat`); `Apps.aip` installs all Apps services as `NT AUTHORITY\LocalService` (node/Java ones wrapped by WinSW, configs in `install/win/runtime/winsw/*.xml`, `Normal` priority); OpenResty and OpenSearch come from their own `.aip`. Linux uses Supervisor (Docker) or systemd (packages)
- Secrets stay off command lines, xtrace and logs: installers pass them through the environment, stdin or files; package configs are `root:onlyoffice` (640/750, `.private` 700); the Windows settings key and install directory are locked to SYSTEM/Administrators
- Installers use dedicated DB/broker accounts on a fresh install (MySQL `<db>_user`, a generated RabbitMQ password instead of `guest`); upgrades keep the working credentials

## Review Focus

**Security**: Hardcoded credentials, injection vulnerabilities, insecure defaults in `.env` and configs, secrets on command lines or in logs
**Docker**: Entrypoint scripts, multi-stage builds, image size, privilege escalation
**Shell/Python**: `set -e`, quoting, error handling in install scripts
**Config**: Sensitive data, default passwords, exposed ports in JSON configs
**CI/CD**: Secret handling, pinned versions, permissions in workflows
**Nginx**: Routing rules in `config/nginx/onlyoffice.conf`, proxy configs

## Git Workflow

- **Main branch**: `master`
- **Integration branch**: `develop`
- **Branch naming**: `feature/*`, `bugfix/*`, `hotfix/*`, `release/*`
