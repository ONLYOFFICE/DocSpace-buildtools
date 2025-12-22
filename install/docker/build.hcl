variable "DOCKERFILE" { default = "Dockerfile.app" }
variable "REGISTRY" { default = "" }
variable "REPO" {}
variable "DOCKER_IMAGE_PREFIX" {}
variable "DOCKER_TAG" {}

target "onlyoffice-backup-background-tasks" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "backup_background"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-backup-background:${DOCKER_TAG}"]
}

target "onlyoffice-clear-events" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "clear-events"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-clear-events:${DOCKER_TAG}"]
}

target "onlyoffice-backup" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "backup"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-backup:${DOCKER_TAG}"]
}

target "onlyoffice-files" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "files"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-files:${DOCKER_TAG}"]
}

target "onlyoffice-files-services" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "files_services"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-files-services:${DOCKER_TAG}"]
}

target "onlyoffice-notify" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "notify"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-notify:${DOCKER_TAG}"]
}

target "onlyoffice-people-server" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "people_server"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-people-server:${DOCKER_TAG}"]
}

target "onlyoffice-socket" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "socket"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-socket:${DOCKER_TAG}"]
}

target "onlyoffice-studio-notify" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "studio_notify"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-studio-notify:${DOCKER_TAG}"]
}

target "onlyoffice-api" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "api"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-api:${DOCKER_TAG}"]
}

target "onlyoffice-api-system" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "api_system"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-api-system:${DOCKER_TAG}"]
}

target "onlyoffice-studio" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "studio"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-studio:${DOCKER_TAG}"]
}

target "onlyoffice-ssoauth" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "ssoauth"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-ssoauth:${DOCKER_TAG}"]
}

target "onlyoffice-ai" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "ai"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-ai:${DOCKER_TAG}"]
}

target "onlyoffice-ai-service" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "ai_service"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-ai-service:${DOCKER_TAG}"]
}

target "onlyoffice-bin-share" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "bin_share"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-bin-share:${DOCKER_TAG}"]
}

target "onlyoffice-wait-bin-share" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "wait_bin_share"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-wait-bin-share:${DOCKER_TAG}"]
}

target "onlyoffice-doceditor" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "doceditor"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-doceditor:${DOCKER_TAG}"]
}

target "onlyoffice-sdk" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "sdk"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-sdk:${DOCKER_TAG}"]
}

target "onlyoffice-management" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "management"
  tags       = ["${REGISTRY}${REPO}/${DOCKER_IMAGE_PREFIX}-management:${DOCKER_TAG}"]
}

target "onlyoffice-login" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "login"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-login:${DOCKER_TAG}"]
}

target "onlyoffice-router" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "router"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-router:${DOCKER_TAG}"]
}

target "onlyoffice-migration-runner" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "onlyoffice-migration-runner"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-migration-runner:${DOCKER_TAG}"]
}

target "onlyoffice-telegram" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "telegram"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-telegram:${DOCKER_TAG}"]
}

target "onlyoffice-healthchecks" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "healthchecks"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-healthchecks:${DOCKER_TAG}"]
}

target "onlyoffice-identity-authorization" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "identity-authorization"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-identity-authorization:${DOCKER_TAG}"]
}

target "onlyoffice-identity-api" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "identity-api"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-identity-api:${DOCKER_TAG}"]
}

target "onlyoffice-dotnet-services" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "dotnet-services"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-dotnet:${DOCKER_TAG}"]
}

target "onlyoffice-java-services" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "java-services"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-java:${DOCKER_TAG}"]
}

target "onlyoffice-node-services" {
  context    = "."
  dockerfile = "${DOCKERFILE}"
  target     = "node-services"
  tags       = ["${REPO}/${DOCKER_IMAGE_PREFIX}-node:${DOCKER_TAG}"]
}

group "default" {
  targets = [
    "onlyoffice-ai",
    "onlyoffice-ai-service",
    "onlyoffice-api",
    "onlyoffice-api-system",
    "onlyoffice-backup",
    "onlyoffice-backup-background-tasks",
    "onlyoffice-bin-share",
    "onlyoffice-clear-events",
    "onlyoffice-doceditor",
    "onlyoffice-dotnet-services",
    "onlyoffice-files",
    "onlyoffice-files-services",
    "onlyoffice-healthchecks",
    "onlyoffice-identity-api",
    "onlyoffice-identity-authorization",
    "onlyoffice-java-services",
    "onlyoffice-login",
    "onlyoffice-management",
    "onlyoffice-migration-runner",
    "onlyoffice-node-services",
    "onlyoffice-notify",
    "onlyoffice-people-server",
    "onlyoffice-router",
    "onlyoffice-sdk",
    "onlyoffice-socket",
    "onlyoffice-ssoauth",
    "onlyoffice-studio",
    "onlyoffice-studio-notify",
    "onlyoffice-telegram",
    "onlyoffice-wait-bin-share",
  ]
}

group "dotnet-services" {
  targets = [
    "onlyoffice-ai",
    "onlyoffice-ai-service",
    "onlyoffice-api",
    "onlyoffice-api-system",
    "onlyoffice-backup",
    "onlyoffice-backup-background-tasks",
    "onlyoffice-bin-share",
    "onlyoffice-clear-events",
    "onlyoffice-dotnet-services",
    "onlyoffice-files",
    "onlyoffice-files-services",
    "onlyoffice-healthchecks",
    "onlyoffice-migration-runner",
    "onlyoffice-notify",
    "onlyoffice-people-server",
    "onlyoffice-studio",
    "onlyoffice-studio-notify",
    "onlyoffice-telegram",
    "onlyoffice-wait-bin-share",
  ]
}

group "node-services" {
  targets = [
    "onlyoffice-node-services",
    "onlyoffice-management",
    "onlyoffice-sdk",
    "onlyoffice-doceditor",
    "onlyoffice-login",
    "onlyoffice-router",
    "onlyoffice-socket",
    "onlyoffice-ssoauth",
  ]
}

group "java-services" {
  targets = [
    "onlyoffice-identity-api",
    "onlyoffice-identity-authorization",
    "onlyoffice-java-services",
  ]
}

