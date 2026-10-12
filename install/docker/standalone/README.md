## Running ONLYOFFICE Apps in Docker

### Overview

The standalone deployment ships ONLYOFFICE Apps as a single-node, monolithic build: all ONLYOFFICE Apps services run in one container instead of separate per-service containers. It's the default topology `apps-install.sh` uses for every edition (Community, Enterprise, Developer), not just for evaluation.

| Container | Role |
| :---- | :---- |
| **onlyoffice-apps** | All ONLYOFFICE Apps services (consolidated) |
| **onlyoffice-document-server** | Document Server (editors) |
| **onlyoffice-mysql-server** | MySQL database |
| **onlyoffice-opensearch** | OpenSearch |

MySQL, OpenSearch and Document Server are each optional here (an external instance can replace the bundled one).

Because everything runs as a single process, this topology does not scale out horizontally (no multiple `onlyoffice-apps` replicas behind a load balancer). If you need that, use the [microservices or stack topology](../Readme.md) instead - the database and its data carry over if you switch later.

**Prerequisites:** Docker Engine with the Compose plugin (docker compose).


### Option 1. Run Images

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2.	Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/standalone
```

Set the blank secrets in `.env` before starting the stack:
`MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `RABBIT_PASSWORD`, and
`DOCUMENT_SERVER_JWT_SECRET`. The OneClickInstall Docker installer generates
them automatically, but plain `docker compose` uses `.env` as-is.

3.	Create the shared Docker network (the stack expects it to already exist; this is a no-op if it's already there):

```bash
docker network create onlyoffice 2>/dev/null || true
```

4.	Start the stack in detached mode:

```bash
docker compose up -d
```

5.	Access ONLYOFFICE Apps at http://localhost or http://your-ip-address.
---

### Option 2. Build Images from Source

Use this option if you want to build ONLYOFFICE Apps images yourself or test changes from a specific branch.

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2. Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/standalone
```

3. Set `MYSQL_ROOT_PASSWORD`, `MYSQL_PASSWORD`, `RABBIT_PASSWORD`, and
   `DOCUMENT_SERVER_JWT_SECRET` in `.env`, as in Option 1.

4. Create the shared Docker network (the stack expects it to already exist; this is a no-op if it's already there):

```bash
docker network create onlyoffice 2>/dev/null || true
```

5. Build and start the containers:

```bash
docker compose up -d --build
```

> **Note:** By default, the images are built from the `master` branch.
> To build from another branch, specify the build argument `GIT_BRANCH`: `GIT_BRANCH=your-branch docker compose up -d --build`

6.	Access ONLYOFFICE Apps at http://localhost or http://your-ip-address.
---

### Option 3. Running with SSL

ONLYOFFICE Apps supports both Let's Encrypt and custom SSL certificates.

> Create the shared network before starting Compose: `docker network create onlyoffice 2>/dev/null || true`

```bash
SSL_MODE="letsencrypt" \
SSL_DOMAIN="example.com,portal.example.com,api.example.com" \
SSL_EMAIL="admin@example.com" \
APP_URL_PORTAL="https://example.com/" \
docker compose up -d
```
> SSL_MODE – SSL certificate mode.
> SSL_DOMAIN – One or more domains separated by commas.
> SSL_EMAIL – Email address used for Let's Encrypt registration.
> APP_URL_PORTAL – Public HTTPS URL of your portal.


If you are using a self-signed certificate or a certificate issued by a private Certificate Authority (CA), the ONLYOFFICE Document Server must also trust this certificate.

Uncomment the following volume in `docker-compose.yml`:

```yaml
services:
   onlyoffice-document-server:
     volumes:
       - ${CERTIFICATE_PATH}:/var/www/onlyoffice/Data/certs/extra-ca-certs.pem
```

Then specify the certificate path on the host:

```bash
SSL_MODE="custom" \
SSL_DOMAIN="example.com" \
SSL_CERT_PATH="/etc/nginx/certs/fullchain.crt" \
SSL_KEY_PATH="/etc/nginx/certs/private.key" \
CERTIFICATE_PATH="./config/nginx/certs/fullchain.crt" \
APP_URL_PORTAL="https://example.com/" \
docker compose up -d
```

> **Note:** `CERTIFICATE_PATH` must point to the certificate file **on the Docker host**, not the path inside the container. This option is typically required only for self-signed certificates or certificates issued by a private CA. Certificates issued by public CAs (for example, Let's Encrypt, DigiCert, or GoDaddy) usually do not require this additional configuration.

> SSL_MODE – SSL certificate mode (custom).
> SSL_DOMAIN – Portal domain name.
> SSL_CERT_PATH – Path to the SSL certificate.
> SSL_KEY_PATH – Path to the private key.
> APP_URL_PORTAL – Public HTTPS URL of your portal.

> **Note:** By default, docker-compose.yml mounts the local ./config/nginx/certs directory to /etc/nginx/certs inside the container.

#### Setting up SSL on a running installation

Instead of passing the variables above by hand, use the [`config/apps-ssl-setup`](config/apps-ssl-setup) helper. It works with the standalone stack (`docker-compose.yml` next to `.env`, `/app/onlyoffice` when installed with `apps-install.sh`), keeps the `SSL_*` settings in `.env` so they survive a container recreate, sets up weekly Let's Encrypt renewal, and mounts a self-signed or private-CA certificate into Document Server as a trusted CA. Run it as root:

```bash
# Let's Encrypt (auto-renew); EMAIL and DOMAIN(s), comma-separated
bash /app/onlyoffice/config/apps-ssl-setup support@example.com example.com,s1.example.com

# bring your own certificate (PEM/PFX/DER/CER/PKCS#7; key required unless PFX)
bash /app/onlyoffice/config/apps-ssl-setup --file example.com /etc/ssl/example.crt /etc/ssl/example.key

# go back to plain HTTP
bash /app/onlyoffice/config/apps-ssl-setup --default
```

> **Note:** Let's Encrypt certificates are kept in `certs/letsencrypt` next to `.env`; wildcard domains (DNS-01) are not renewed automatically. Run the script without arguments for full usage.


Access ONLYOFFICE Apps at https://example.com/.
