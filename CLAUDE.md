# Claude Code Review Context

## Repository

ONLYOFFICE DocSpace Build Tools — build scripts, Docker configurations, installation packages, CI/CD pipelines, and application configuration.

**Environment**: Gitea Actions (not GitHub), standard git operations, some GitHub Actions features may differ

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

## Review Workflow

**Context**: Read [README.md](README.md) to understand project architecture, setup instructions, and deployment practices before reviewing code.

### 1. Check Previous Reviews

- Find comments from `gitea-actions` or `claude`
- If fixed → acknowledge: `☑️ Fixed: [title]`
- If NOT fixed → re-raise with **original severity** (do NOT escalate based on repetition count)
- Focus on new changes only

### 2. Output Format

```html
<details>
<summary>[VERDICT(✅ APPROVE (only Low/Positive) or ❌ REQUEST_CHANGES (has Critical/Medium))] - Claude Code Review</summary>

---

###📋 PR Summary
- **What**: Brief description of the main changes.
- **Why**: Reason or motivation for the changes.
- **Scope**: Which files, components, directories are affected.
- **Details** (optional):
	- If the changes affect project structure, list new, deleted, or moved files/directories.
	- If there are important technical decisions, briefly describe them.
	- If there are breaking changes, state them explicitly.

---

### �🔄 Previous Review Follow-up
⚪️ **Fixed**: [title] - brief note
[🔴/🟡/🔵] **Still Open**: [title] (original severity: [emoji]) - why still relevant

---

### 🔒 Security Issues
<details><summary>🔴 Critical: Issue Title</summary>

- **File**: `path/file.ext:42`
- **Why**: Problem explanation
- **Fix**: Solution with code example

</details>

---

### 🐛 Code Quality
<details><summary>🟡 Medium: Issue Title</summary>...</details>

---

### ✅ Positive Observations
- **Feature**: Description

---

### 📝 Documentation Updates Required
- **README.md**: [what and why]
- **CLOUDE.md**: [what and why]

</details>
```

**Verdict logic:**
- `✅ APPROVE` — only 🔵 Low or ✅ Positive issues
- `❌ REQUEST_CHANGES` — at least one 🔴 Critical or 🟡 Medium issue found

**Formatting:** 🔴 Critical | 🟡 Medium | 🔵 Low | ✅ Positive | 💡 Recommendation

**Requirements:**
- Separate sections with `---`
- Wrap issues in `<details><summary>`
- Group by category (🔒 Security, 🐛 Quality, 💅 Style)
- Include file:line, impact, actionable fix
- Add before/after code examples

## Coding Standards

**Shell**: `set -e`, proper quoting | **Python**: Python 3 | **JSON**: no comments | **Docker**: multi-stage, minimal layers | **Secrets**: env vars only
