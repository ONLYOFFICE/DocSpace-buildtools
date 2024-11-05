# ONLYOFFICE DocSpace Installation Guide 

## Step 1: Download the Installation Script
Download the appropriate OneClickInstall script based on the version you want to install:

- **Enterprise**:
    ```bash
    wget https://download.onlyoffice.com/docspace/docspace-enterprise-install.sh
    ```
- **Developer**:
    ```bash
    wget https://download.onlyoffice.com/docspace/docspace-developer-install.sh
    ```
- **Community**:
    ```bash
    wget https://download.onlyoffice.com/docspace/docspace-install.sh
    ```

## Step 2: Run the Installation
Use the downloaded script to install ONLYOFFICE DocSpace with either the RPM/DEB package or Docker.

- **Install as RPM/DEB Package**:
    ```bash
    bash <script-name> package
    ```

- **Install as Docker**:
    ```bash
    bash <script-name> docker
    ```

Replace `<script-name>` with the name of the downloaded script (e.g., `docspace-enterprise-install.sh`).

## Step 3: Display Available Parameters (Optional)
Each script provides optional parameters for advanced configuration. Use the following commands to view them:

- **Display RPM/DEB Parameters**:
    ```bash
    bash <script-name> package -h
    ```

- **Display Docker Parameters**:
    ```bash
    bash <script-name> docker -h
    ```

Replace `<script-name>` with the appropriate script file as used in Step 2.