## Running ONLYOFFICE DocSpace in Docker (draft)

> **Note:** Not for production use.
> This guide deploys a development/testing build of ONLYOFFICE DocSpace.
> It serves over plain HTTP (no TLS), ships without identity/OAuth services, and runs a reduced feature set.
> For production deployments, use the: [Production Version of ONLYOFFICE DocSpace](https://www.onlyoffice.com/download.aspx#docspace-enterprise)

### Overview

This preview ships ONLYOFFICE DocSpace as a monolithic build: all ONLYOFFICE DocSpace services run in a single container rather than as separate per-service containers. The full stack consists of three containers:

| Container | Role |
| :---- | :---- |
| **onlyoffice-docspace-preview** | All ONLYOFFICE DocSpace services (consolidated) |
| **docspaceonlyoffice-document-server** | Document Server (editors) |
| **onlyoffice-mysql-server** | MySQL database |

Differences from the standard multi-container deployment:
•	All ONLYOFFICE DocSpace services are consolidated into a single container.
•	Simplified search.
•	No thumbnail generation.
•	HTTP only — no TLS/HTTPS.
•	No identity/OAuth services.

**Prerequisites:** Docker Engine with the Compose plugin (docker compose).


### Option 1. Run Prebuilt Images

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2.	Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/preview
```

3.	Start the stack in detached mode:

```bash
docker compose up -d
```

4.	Access ONLYOFFICE DocSpace at http://localhost.

---

### Option 2. Build Images from Source

Use this option if you want to build DocSpace images yourself or test changes from a specific branch.

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2. Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/preview
```

3. Build and start the containers:

```bash
docker compose up -d --build
```

> **Note:** By default, the images are built from the `master` branch.
> To build from another branch, specify the build argument `GIT_BRANCH`: `GIT_BRANCH=your-branch docker compose up -d --build`

4.	Access ONLYOFFICE DocSpace at http://localhost.
