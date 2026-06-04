## Running ONLYOFFICE DocSpace in Docker

> **Note:** DO NOT USE THIS VERSION IN PRODUCTION ENVIRONMENTS.
> The following instructions create a **development/testing environment** and are not suitable for production use.
>
> For production deployment, see:
> [Production Version of ONLYOFFICE DocSpace](https://www.onlyoffice.com/download.aspx#docspace-enterprise)

### Option 1. Run Prebuilt Images

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2. Navigate to the Docker preview directory:

```bash
cd DocSpace-buildtools/install/docker/preview
```

3. Start the containers:

```bash
docker compose up -d
```

Open ONLYOFFICE DocSpace in your browser: http://localhost

---

### Option 2. Build Images from Source

Use this option if you want to build DocSpace images yourself or test changes from a specific branch.

1. Clone the repository:

```bash
git clone https://github.com/ONLYOFFICE/DocSpace-buildtools.git
```

2. Navigate to the Docker preview directory:

```bash
cd DocSpace-buildtools/install/docker/preview
```

3. Build and start the containers:

```bash
docker compose up -d --build
```

> **Note:** 
> By default, the images are built from the `master` branch.
> To build from another branch, specify the build argument `GIT_BRANCH`: `GIT_BRANCH=your-branch docker compose up -d --build`

Open ONLYOFFICE DocSpace in your browser: http://localhost
