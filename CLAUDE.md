## Project Overview

ONLYOFFICE DocSpace Build Tools — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration.

## Tech Stack

.NET (C#), Java, Node.js, Docker, Nginx, Supervisor, MySQL, Redis, RabbitMQ, OpenSearch

## Project Structure

```
config/          — JSON configs, nginx
install/docker/  — Dockerfiles, Compose, .env
install/OneClickInstall/ — Linux/Docker installers
install/win/     — Windows installer (.aip)
install/deb|rpm/ — Package metadata
run/             — Service launch scripts
.github|.gitea/workflows/ — CI/CD pipelines
*.py|*.sh|*.bat  — Build scripts
```

## Review Focus

**Security**: Hardcoded credentials, injection vulnerabilities, insecure defaults  
**Docker**: Multi-stage builds, image size, privilege escalation  
**Shell**: Quoting, error handling (`set -e`), portability  
**Config**: Sensitive data, default passwords, exposed ports  
**CI/CD**: Secret handling, pinned versions, permissions  
**Dependencies**: CVEs, outdated packages

## Key Patterns

- RabbitMQ for messaging, Redis for cache, Nginx for routing
- Supervisor manages .NET/Node.js/Java processes
- Three editions: Community, Enterprise, Developer
- All config via environment variables in `.env`

## Coding Standards

**Shell**: `set -e`, proper quoting | **Python**: Python 3 | **JSON**: no comments | **Docker**: multi-stage, minimal layers | **Secrets**: env vars only
