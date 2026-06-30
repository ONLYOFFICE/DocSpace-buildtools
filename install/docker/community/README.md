## Running ONLYOFFICE DocSpace in Docker

> **Note:** Not for production use.
> This guide deploys a development/testing build of ONLYOFFICE DocSpace.
> For production deployments, use the: [Production Version of ONLYOFFICE DocSpace](https://www.onlyoffice.com/download.aspx#docspace-enterprise)

### Overview

This community ships ONLYOFFICE DocSpace as a monolithic build: all ONLYOFFICE DocSpace services run in a single container rather than as separate per-service containers. The full stack consists of four containers:

| Container | Role |
| :---- | :---- |
| **onlyoffice-docspace** | All ONLYOFFICE DocSpace services (consolidated) |
| **onlyoffice-document-server** | Document Server (editors) |
| **onlyoffice-mysql-server** | MySQL database |
| **onlyoffice-opensearch** | OpenSearch |

Differences from the standard multi-container deployment:

- All ONLYOFFICE DocSpace services are consolidated into a single container.
- No thumbnail generation.

**Prerequisites:** Docker Engine with the Compose plugin (docker compose).


### Option 1. Run Images

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2.	Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/community
```

3.	Start the stack in detached mode:

```bash
docker compose up -d
```

4.	Access ONLYOFFICE DocSpace at http://localhost or http://your-ip-address.
---

### Option 2. Build Images from Source

Use this option if you want to build DocSpace images yourself or test changes from a specific branch.

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2. Change into the Compose directory:

```bash
cd DocSpace-buildtools/install/docker/community
```

3. Build and start the containers:

```bash
docker compose up -d --build
```

> **Note:** By default, the images are built from the `master` branch.
> To build from another branch, specify the build argument `GIT_BRANCH`: `GIT_BRANCH=your-branch docker compose up -d --build`

4.	Access ONLYOFFICE DocSpace at http://localhost or http://your-ip-address.
---

### Option 3. Running with SSL

DocSpace supports both Let's Encrypt and custom SSL certificates.

```bash
SSL_MODE="letsencrypt" \
SSL_DOMAIN="example.com,portal.example.com,api.example.com" \
SSL_EMAIL="admin@example.com" \
APP_URL_PORTAL="https://example.com/" \
docker compose \
  -f docker-compose.yml \
  -f ssl.yml \
  up -d
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
docker compose \
  -f docker-compose.yml \
  -f ssl.yml \
  up -d
```

> **Note:** `CERTIFICATE_PATH` must point to the certificate file **on the Docker host**, not the path inside the container. This option is typically required only for self-signed certificates or certificates issued by a private CA. Certificates issued by public CAs (for example, Let's Encrypt, DigiCert, or GoDaddy) usually do not require this additional configuration.

> SSL_MODE – SSL certificate mode (custom).
> SSL_DOMAIN – Portal domain name.
> SSL_CERT_PATH – Path to the SSL certificate.
> SSL_KEY_PATH – Path to the private key.
> APP_URL_PORTAL – Public HTTPS URL of your portal.

> **Note:** By default, the ssl.yml configuration mounts the local ./config/nginx/certs directory to /etc/nginx/certs inside the container.


Access ONLYOFFICE DocSpace at https://example.com/.