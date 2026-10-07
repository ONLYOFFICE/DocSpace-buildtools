#!/bin/bash

 #
 # Copyright (C) Ascensio System SIA, 2009-2026
 #
 # This program is a free software product. You can redistribute it and/or
 # modify it under the terms of the GNU Affero General Public License (AGPL)
 # version 3 as published by the Free Software Foundation, together with the
 # additional terms provided in the LICENSE file.
 #
 # This program is distributed WITHOUT ANY WARRANTY; without even the implied
 # warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. For
 # details, see the GNU AGPL at: https://www.gnu.org/licenses/agpl-3.0.html
 #
 # You can contact Ascensio System SIA by email at info@onlyoffice.com
 # or by postal mail at 20A-6 Ernesta Birznieka-Upisha Street, Riga,
 # LV-1050, Latvia, European Union.
 #
 # The interactive user interfaces in modified versions of the Program
 # are required to display Appropriate Legal Notices in accordance with
 # Section 5 of the GNU AGPL version 3.
 #
 # No trademark rights are granted under this License.
 #
 # All non-code elements of the Product, including illustrations,
 # icon sets, and technical writing content, are licensed under the
 # Creative Commons Attribution-ShareAlike 4.0 International License:
 # https://creativecommons.org/licenses/by-sa/4.0/legalcode
 #
 # This license applies only to such non-code elements and does not
 # modify or replace the licensing terms applicable to the Program's
 # source code, which remains licensed under the GNU Affero General
 # Public License v3.
 #
 # SPDX-License-Identifier: AGPL-3.0-only
 #

# Sourced by install-Docker.sh. Uses installer configuration and shared helpers.
# Contains Docs adoption, mount preservation, rollback and HTTPS handoff.

# Classify every actual mount, including anonymous volumes created by the image.
# Fonts stay mounted at their original paths: an image VOLUME below /usr/share/fonts
# would otherwise hide files copied into the parent ds_fonts volume.
# Mounts nested below a managed path (OneClickInstall-Docs "forgotten") migrate into its volume.
plan_document_server_mounts () {
	local INSPECT SOURCE REAL_SOURCE REAL_BASE
	INSPECT=$(cat) || return 1
	REAL_BASE=$(readlink -m -- "${BASE_DIR}") || return 1
	# Docker may retain a symlink in Mounts.Source. Check its actual location
	# before download_files removes old installer files.
	while IFS= read -r -d '' SOURCE; do
		REAL_SOURCE=$(readlink -m -- "${SOURCE}") || return 1
		case "${REAL_BASE%/}/" in
			"${REAL_SOURCE%/}/"*)
				echo "Docs bind mount overlaps the installer directory: ${SOURCE}" >&2
				return 1 ;;
		esac
		case "${REAL_SOURCE%/}/" in
			"${REAL_BASE%/}/DocumentServer/"*|"${REAL_BASE%/}/certs/"*) ;;
			"${REAL_BASE%/}/"*)
				echo "Docs bind mount resolves inside the installer directory: ${SOURCE}" >&2
				return 1 ;;
		esac
	done < <(jq -j '.[0].Mounts[] | select(.Type == "bind") | .Source, "\u0000"' <<<"${INSPECT}")
	jq -ce --arg base "${BASE_DIR%/}" '
		def managed: {
			"/var/www/onlyoffice/Data": "app_data",
			"/var/log/onlyoffice": "log_data",
			"/var/lib/onlyoffice": "ds_state",
			"/var/lib/postgresql": "ds_postgresql"
		};
		def beneath($a; $b): $a == $b or ($a | startswith($b + "/"));
		def owner($dest): [managed | to_entries[] | select(beneath($dest; .key))] | sort_by(.key | length) | last // null;
		.[0] as $c |
		if (($c.HostConfig.Tmpfs // {}) | length) > 0 then
			error("Docs has tmpfs mounts; migrate them explicitly before adoption")
		else . end |
		[$c.Mounts[] |
			. as $m |
			([$c.HostConfig.Mounts[]? | select(.Target == $m.Destination)][0] // {}) as $spec |
			(.Mode // "" | split(",") | map(select(length > 0))) as $modes |
			owner(.Destination) as $owner |
			($owner.value // null) as $managed |
			(if $owner != null then .Destination[($owner.key | length):] | ltrimstr("/") else "" end) as $subdir |
			if (.Type != "bind" and .Type != "volume") then
				error("Unsupported Docs mount type at " + .Destination)
			elif ([.Source, .Destination, (.Name // "")] | any(test("[\r\n\t]"))) then
				error("Unsupported control character in Docs mount")
			elif .Type == "bind" and
				(beneath($base; .Source) or (beneath(.Source; $base) and
				 (beneath(.Source; $base + "/DocumentServer") or beneath(.Source; $base + "/certs") | not))) then
				error("Docs bind mount overlaps the installer directory: " + .Source)
			elif $managed != null and .RW != true then
				error("Cannot migrate a read-only managed Docs mount: " + .Destination)
			elif $managed == null and (managed | keys | any(beneath(.; $m.Destination))) then
				error("Docs mount hides a managed data path: " + .Destination)
			elif (($spec.BindOptions // {} | del(.Propagation, .CreateMountpoint)) | length) > 0 then
				error("Unsupported bind options at " + .Destination)
			elif ($modes - ["rw", "ro", "z", "Z", "private", "rprivate", "shared", "rshared", "slave", "rslave", "cached", "delegated", "consistent", "nocopy"] | length) > 0 then
				error("Unsupported mount mode at " + .Destination)
			elif (.Type == "volume" and (.Name // "") == "") then
				error("Missing Docker volume name at " + .Destination)
			else . end |
			{
				type: .Type, source: (if .Type == "volume" then .Name else .Source end),
				target: .Destination, read_only: (.RW | not), managed: $managed, subdir: $subdir,
				propagation: ([$spec.BindOptions.Propagation, .Propagation] | map(select(. != null and . != "")) | first // "rprivate"),
				selinux: ($modes | map(select(. == "z" or . == "Z")) | first // null),
				consistency: ($modes | map(select(. == "cached" or . == "delegated" or . == "consistent")) | first // null),
				nocopy: ($spec.VolumeOptions.NoCopy // ($modes | index("nocopy") != null)),
				subpath: ($spec.VolumeOptions.Subpath // null)
			} |
			if .subpath != null and (.subpath | startswith("/") or (split("/") | index("..") != null)) then
				error("Invalid volume subpath at " + .target)
			else . end
		]
	' <<<"${INSPECT}"
}

# Explicit -f options disable Compose automatic override loading. Route installer
# operations involving Docs through this function, including updates and teardown.
compose_with_document_server_mounts () {
	local ARGS=() HAS_DOCS=false RESULT INFO
	while [ "$#" -gt 0 ] && { [ "$1" = "-f" ] || [ "$1" = "--file" ]; }; do
		case "${2##*/}" in ds.yml|docker-compose.yml) HAS_DOCS=true ;; esac
		ARGS+=("$1" "$2")
		shift 2
	done
	if [ "${HAS_DOCS}" = true ] && [ -f "${BASE_DIR}/config/ds-mounts.json" ]; then
		ARGS+=(-f "${BASE_DIR}/config/ds-mounts.json")
	fi
	${DOCKER_COMPOSE} "${ARGS[@]}" "$@"
	RESULT=$?
	# Record only a new Compose Docs container, so rollback cannot remove the source.
	if [ "${DS_ADOPTION_ACTIVE}" = true ] && [ "$1" = up ] && [ -n "${DS_NEW_CONTAINER_NAME}" ]; then
		INFO=$(docker inspect --type container "${DS_NEW_CONTAINER_NAME}" 2>/dev/null) || INFO='[]'
		DS_NEW_CONTAINER_ID=$(jq -r --arg old "${DS_ORIGINAL_ID}" \
			'.[0] | select(.Id != $old and .Config.Labels["com.docker.compose.service"] == "onlyoffice-document-server") | .Id // empty' <<<"${INFO}")
		if [ "${DEPLOYMENT_MODE}" = standalone ]; then
			INFO=$(docker inspect --type container "${CONTAINER_NAME}" 2>/dev/null) || INFO='[]'
			DS_NEW_FRONTEND_ID=$(jq -r --arg old "${DS_EXISTING_FRONTEND_ID}" --arg service "${PACKAGE_SYSNAME}-${PRODUCT}" \
				'.[0] | select(.Id != $old and .Config.Labels["com.docker.compose.service"] == $service) | .Id // empty' <<<"${INFO}")
		fi
	fi
	return "${RESULT}"
}

rollback_document_server_migration () {
	[ "${DS_ADOPTION_ACTIVE}" = true ] || return 0
	echo "Restoring the original Docs container ${DS_ORIGINAL_NAME}..." >&2
	# Remove the newly created front end to release the original Docs ports
	# and prevent the next installer run from treating this failed adoption
	# as an existing Apps installation.
	if [ -n "${DS_NEW_FRONTEND_ID}" ]; then
		docker rm -f "${DS_NEW_FRONTEND_ID}" >/dev/null || return 1
	fi
	if [ -n "${DS_NEW_CONTAINER_ID}" ]; then
		docker rm -f "${DS_NEW_CONTAINER_ID}" >/dev/null || {
			echo "Cannot remove the replacement Docs container; the original remains stopped to avoid concurrent writes." >&2
			return 1
		}
	fi
	if [ "${DS_ORIGINAL_RENAMED}" = true ]; then
		docker rename "${DS_ORIGINAL_ID}" "${DS_ORIGINAL_NAME}" || return 1
	fi
	if [ "${DS_ORIGINAL_RUNNING}" = true ]; then
		docker start "${DS_ORIGINAL_ID}" >/dev/null || {
			echo "The original Docs container is retained but could not be restarted." >&2
			return 1
		}
	fi
	DS_ADOPTION_ACTIVE=false
}

detect_existing_document_server () {
	[ "${UPDATE}" = "true" ] && return 0
	[ "${INSTALL_DOCUMENT_SERVER}" = "true" ] || return 0

	local CONTAINER FOUND_IMAGE CANDIDATE
	# The status prefix is optional, so release images are adopted under any --status.
	while read -r CANDIDATE FOUND_IMAGE; do
		# Adopt only raw docker-run Docs containers.
		[ -n "$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "${CANDIDATE}" 2>/dev/null)" ] && continue
		CONTAINER="${CANDIDATE}"
		break
	done < <(docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null | awk -v pkg="${PACKAGE_SYSNAME}" -v status="${STATUS}" 'BEGIN {prefix = (status == "") ? "" : "(" status ")?"} $2 ~ ("(^|/)"pkg"/"prefix"documentserver(-de|-ee)?(:|$)") {print}')
	[ -z "${CONTAINER}" ] && return 0

	# Inspect before stopping or recreating anything; mount options must survive too.
	DS_CONTAINER_INSPECT=$(docker inspect --type container "${CONTAINER}") || return 1
	DS_MOUNT_PLAN=$(plan_document_server_mounts <<<"${DS_CONTAINER_INSPECT}") || return 1
	DS_ORIGINAL_ID=$(jq -r '.[0].Id' <<<"${DS_CONTAINER_INSPECT}")
	DS_ORIGINAL_NAME="${CONTAINER}"
	DS_ORIGINAL_RUNNING=$(jq -r '.[0].State.Running' <<<"${DS_CONTAINER_INSPECT}")
	DS_EXISTING_FRONTEND_ID=$(docker inspect --format '{{.Id}}' "${CONTAINER_NAME}" 2>/dev/null) || DS_EXISTING_FRONTEND_ID=""
	DS_ADOPTION_ACTIVE=true
	DS_PREVIOUS_EXIT_TRAP=$(trap -p EXIT)
	trap 'DS_EXIT_STATUS=$?; rollback_document_server_migration; exit "${DS_EXIT_STATUS}"' EXIT
	jq -r '.[] | "Docs mount: " + .source + " -> " + .target + " (" +
		(if .managed then "copy to " + .managed else "keep original mount" end) + ")"' <<<"${DS_MOUNT_PLAN}"

	echo "Found an existing Document Server container (${CONTAINER}); attaching it instead of deploying a new one."

	# Keep the detected edition/tag when adopting.
	DOCUMENT_SERVER_IMAGE_NAME="${FOUND_IMAGE}"
	if [[ "${FOUND_IMAGE}" == *:* ]] && [[ "${FOUND_IMAGE##*:}" != */* ]]; then
		# Avoid treating registry:port as an image tag.
		DOCUMENT_SERVER_IMAGE_NAME="${FOUND_IMAGE%:*}"
		DOCUMENT_SERVER_VERSION="${FOUND_IMAGE##*:}"
	fi

	# Inherit HTTPS before moving Docs behind ds.yml's port 80.
	DS_HTTPS_INHERITED="false"
	local DS_SSL_CERT DS_SSL_KEY DS_SSL_DOMAIN DS_CONF_CONTENT
	if [ "${INSTALL_PRODUCT}" == "true" ] && [ -z "${CERTIFICATE_PATH}" ] && [ -z "${LETS_ENCRYPT_DOMAIN}" ]; then
		DS_CONF_CONTENT="$(docker exec "${CONTAINER}" sh -c '[ -f /etc/onlyoffice/documentserver/nginx/ds.conf ] && [ ! -L /etc/onlyoffice/documentserver/nginx/ds.conf ] && cat /etc/onlyoffice/documentserver/nginx/ds.conf' 2>/dev/null)"
	fi
	if [ -n "${DS_CONF_CONTENT}" ]; then
		DS_SSL_CERT="$(grep -oP '^\s*ssl_certificate\s+\K[^;]+' <<< "$DS_CONF_CONTENT" | head -1)"
		DS_SSL_KEY="$(grep -oP '^\s*ssl_certificate_key\s+\K[^;]+' <<< "$DS_CONF_CONTENT" | head -1)"
		DS_SSL_DOMAIN="$(grep -oP '^\s*server_name\s+\K\S+' <<< "$DS_CONF_CONTENT" | grep -vE '^(_|localhost);?$' | head -1 | sed 's/^\*\.//')"
		DS_SSL_DOMAIN="${DS_SSL_DOMAIN%;}"
		# Static cert configs may need SAN/CN fallback.
		[ -z "${DS_SSL_DOMAIN}" ] && [ -n "${DS_SSL_CERT}" ] && \
			DS_SSL_DOMAIN="$(docker exec "${CONTAINER}" openssl x509 -noout -ext subjectAltName -subject -in "${DS_SSL_CERT}" 2>/dev/null | grep -oP 'DNS:\K[^, ]+|CN\s*=\s*\K[^,/]+' | head -1 | sed 's/^\*\.//')"

		if [ -n "${DS_SSL_CERT}" ] && [ -n "${DS_SSL_KEY}" ] && [ -n "${DS_SSL_DOMAIN}" ]; then
			# LE certs would be lost on recreate; request a new managed cert instead.
			local DS_LETS_ENCRYPT_MAIL=""
			if [[ "${DS_SSL_CERT}" == /etc/letsencrypt/live/*/fullchain.pem ]]; then
				DS_LETS_ENCRYPT_MAIL="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${CONTAINER}" 2>/dev/null | sed -n 's/^LETS_ENCRYPT_MAIL=//p' | head -1)"
			fi
			if [ -n "${DS_LETS_ENCRYPT_MAIL}" ]; then
				echo "${CONTAINER} is serving HTTPS for ${DS_SSL_DOMAIN} via Let's Encrypt; ${PRODUCT_NAME} will request and manage its own certificate for the same domain."
				LETS_ENCRYPT_DOMAIN="${LETS_ENCRYPT_DOMAIN:-${DS_SSL_DOMAIN}}"
				LETS_ENCRYPT_MAIL="${LETS_ENCRYPT_MAIL:-${DS_LETS_ENCRYPT_MAIL}}"
				APP_DOMAIN_PORTAL="${APP_DOMAIN_PORTAL:-${DS_SSL_DOMAIN}}"
				DS_HTTPS_INHERITED="true"
			else
				mkdir -p "${BASE_DIR}/certs"
				# Copy the resolved Let's Encrypt certificate, not the symlink.
				if docker cp -L "${CONTAINER}:${DS_SSL_CERT}" "${BASE_DIR}/certs/ds-inherited.crt" >/dev/null 2>&1 \
					&& docker cp -L "${CONTAINER}:${DS_SSL_KEY}" "${BASE_DIR}/certs/ds-inherited.key" >/dev/null 2>&1; then
					echo "${CONTAINER} is serving HTTPS for ${DS_SSL_DOMAIN}; ${PRODUCT_NAME} will take over as the HTTPS front end with the same certificate."
					CERTIFICATE_PATH="${BASE_DIR}/certs/ds-inherited.crt"
					CERTIFICATE_KEY_PATH="${BASE_DIR}/certs/ds-inherited.key"
					APP_DOMAIN_PORTAL="${APP_DOMAIN_PORTAL:-${DS_SSL_DOMAIN}}"
					DS_HTTPS_INHERITED="true"
				else
					echo "Warning: ${CONTAINER} looks HTTPS-configured but its certificate could not be extracted; installing ${PRODUCT_NAME} on http://${EXTERNAL_PORT}." >&2
				fi
			fi
		fi
	fi

	# Only published-port conflicts require recreation here.
	local PORT_CONFLICT="false" PUBLISHED_PORTS
	if [ "${INSTALL_PRODUCT}" == "true" ]; then
		PUBLISHED_PORTS="$(docker port "${CONTAINER}" 2>/dev/null)"
		grep -qE ":${EXTERNAL_PORT}$" <<<"${PUBLISHED_PORTS}" && PORT_CONFLICT="true"
		if [[ -n "$CERTIFICATE_PATH" ]] || [[ -n "$LETS_ENCRYPT_DOMAIN" ]] || [ "${DEPLOYMENT_MODE}" = standalone ]; then
			grep -qE ":${EXTERNAL_PORT_HTTPS}$" <<<"${PUBLISHED_PORTS}" && PORT_CONFLICT="true"
		fi
	fi

	if [ "${PORT_CONFLICT}" = "true" ]; then
		echo "Stopping ${CONTAINER} to release its published ports; keeping it for rollback."
		docker stop "${DS_ORIGINAL_ID}" >/dev/null || return 1
	fi

	DOCUMENT_SERVER_HOST="${CONTAINER}"
	DOCUMENT_SERVER_PORT="80"
	INSTALL_DOCUMENT_SERVER="false"
	DOCUMENT_SERVER_ATTACHED="true"
}

set_docs_url_external () {
	DOCUMENT_SERVER_URL_EXTERNAL=${DOCUMENT_SERVER_URL_EXTERNAL:-$(get_env_parameter "DOCUMENT_SERVER_URL_EXTERNAL" "${CONTAINER_NAME}")}

	if [[ ! -z ${DOCUMENT_SERVER_URL_EXTERNAL} ]] && [[ $DOCUMENT_SERVER_URL_EXTERNAL =~ ^(https?://)?([^:/]+)(:([0-9]+))?(/.*)?$ ]]; then
		[[ -z ${BASH_REMATCH[1]} ]] && DOCUMENT_SERVER_URL_EXTERNAL="http://$DOCUMENT_SERVER_URL_EXTERNAL"
		DOCUMENT_SERVER_PROTOCOL="${BASH_REMATCH[1]}"
		DOCUMENT_SERVER_HOST="${BASH_REMATCH[2]}"
		DOCUMENT_SERVER_PORT="${BASH_REMATCH[4]:-"80"}"
	fi
}

set_jwt_secret () {
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_env_parameter "JWT_SECRET" "${PACKAGE_SYSNAME}-document-server")}"
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_env_parameter "DOCUMENT_SERVER_JWT_SECRET" "${CONTAINER_NAME}")}"
	[ "${DOCUMENT_SERVER_ATTACHED}" = "true" ] && \
		DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_env_parameter "JWT_SECRET" "${DOCUMENT_SERVER_HOST}")}"
	DOCUMENT_SERVER_JWT_SECRET="${DOCUMENT_SERVER_JWT_SECRET:-$(get_random_str 32)}"
}

set_jwt_header () {
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-$(get_env_parameter "JWT_HEADER" "${PACKAGE_SYSNAME}-document-server")}"
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-$(get_env_parameter "DOCUMENT_SERVER_JWT_HEADER" "${CONTAINER_NAME}")}"
	[ "${DOCUMENT_SERVER_ATTACHED}" = "true" ] && \
		DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-$(get_env_parameter "JWT_HEADER" "${DOCUMENT_SERVER_HOST}")}"
	DOCUMENT_SERVER_JWT_HEADER="${DOCUMENT_SERVER_JWT_HEADER:-"AuthorizationJwt"}"
}

enable_document_server_env_file () {
	local COMPOSE_FILE="$1"
	if [ -s "${BASE_DIR}/config/ds.env" ]; then
		sed -i -e 's/^\( *\)#env_file:[[:space:]]*$/\1env_file:/' -e 's/^ *#  - config\/ds\.env[[:space:]]*$/      - config\/ds.env/' "${COMPOSE_FILE}"
	fi
}

# Resolve a ds.yml volume path, creating the bind/volume if needed.
resolve_ds_volume_path () {
	local NAME="$1"
	if [ -n "${VOLUMES_DIR}" ]; then
		mkdir -p "${VOLUMES_DIR}/${NAME}" || return 1
		echo "${VOLUMES_DIR}/${NAME}"
	else
		local PROJECT_NAME="${COMPOSE_PROJECT_NAME:-${PACKAGE_SYSNAME}}"
		docker volume inspect "${PROJECT_NAME}_${NAME}" >/dev/null 2>&1 || docker volume create \
			--label "com.docker.compose.project=${PROJECT_NAME}" \
			--label "com.docker.compose.volume=${NAME}" \
			"${PROJECT_NAME}_${NAME}" >/dev/null || return 1
		docker volume inspect --format '{{.Mountpoint}}' "${PROJECT_NAME}_${NAME}"
	fi
}

write_document_server_mounts () {
	local MOUNTS_TMP HOST_NAME
	HOST_NAME=$(jq -r '.[0].Config.Hostname // empty' <<<"${DS_CONTAINER_INSPECT:-null}") || return 1
	mkdir -p "${BASE_DIR}/config" || return 1
	MOUNTS_TMP=$(mktemp "${BASE_DIR}/config/.ds-mounts.XXXXXX") || return 1
	# JSON is a Compose input format. Escape dollar signs against interpolation;
	# external volumes also protect anonymous Docker volumes from compose down -v.
	if ! jq --arg hostname "${HOST_NAME}" '
		map(select(.managed == null)) | to_entries as $entries |
		{
			services: {"onlyoffice-document-server": ({
				volumes: [$entries[] | .key as $i | .value |
					{type, target, read_only,
					 source: (if .type == "volume" then "adopted_docs_" + ($i | tostring) else .source end)} +
					(if .type == "bind" then
						{bind: ({create_host_path: false, propagation} +
							(if .selinux then {selinux} else {} end))}
					 else {volume: ({nocopy} + (if .subpath then {subpath} else {} end))} end) +
					(if .consistency then {consistency} else {} end)
				]
			} + (if $hostname != "" then {hostname: $hostname} else {} end))},
			volumes: ([$entries[] | select(.value.type == "volume") |
				{key: ("adopted_docs_" + (.key | tostring)), value: {external: true, name: .value.source}}] | from_entries)
		} |
		(.. | strings) |= gsub("\\$"; "$$")
	' <<<"${DS_MOUNT_PLAN}" > "${MOUNTS_TMP}"; then
		rm -f "${MOUNTS_TMP}"
		return 1
	fi
	mv -f "${MOUNTS_TMP}" "${BASE_DIR}/config/ds-mounts.json"
}

# Move adopted Docs data into the volumes declared by ds.yml.
migrate_document_server_data () {
	local DS_COMPOSE_FILE="${BASE_DIR}/ds.yml"
	[ "${DEPLOYMENT_MODE}" = standalone ] && DS_COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
	write_document_server_mounts || return 1

	# Keep only env values changed from image defaults.
	local IMAGE_REF DEFAULT_KEY DEFAULT_VAL
	local -A IMAGE_DEFAULT_ENV=()
	IMAGE_REF=$(jq -r '.[0].Image' <<<"${DS_CONTAINER_INSPECT}")
	while IFS='=' read -r DEFAULT_KEY DEFAULT_VAL; do
		[ -n "${DEFAULT_KEY}" ] && IMAGE_DEFAULT_ENV["${DEFAULT_KEY}"]="${DEFAULT_VAL}"
	done < <(docker image inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "${IMAGE_REF}" 2>/dev/null)

	local ENV_LINE ENV_KEY ENV_VAL
	mkdir -p "${BASE_DIR}/config" || return 1
	(umask 077; : > "${BASE_DIR}/config/ds.env") || return 1
	while IFS= read -r ENV_LINE; do
		ENV_KEY="${ENV_LINE%%=*}"
		ENV_VAL="${ENV_LINE#*=}"
		[ -z "${ENV_KEY}" ] && continue
		case "${ENV_KEY}" in
			JWT_ENABLED|JWT_SECRET|JWT_HEADER|JWT_IN_BODY|AMQP_URI|REDIS_SERVER_HOST|REDIS_SERVER_PORT|REDIS_SERVER_USER|REDIS_SERVER_PASS|REDIS_SERVER_DB|PATH|HOME|HOSTNAME) continue ;;
			# LE state would be lost; the new front end owns renewal.
			LETS_ENCRYPT_DOMAIN|LETS_ENCRYPT_MAIL) continue ;;
		esac
		[ "${IMAGE_DEFAULT_ENV[${ENV_KEY}]-__unset__}" = "${ENV_VAL}" ] && continue
		printf '%s\n' "${ENV_LINE}" >> "${BASE_DIR}/config/ds.env" || return 1
	done < <(jq -r '.[0].Config.Env[]' <<<"${DS_CONTAINER_INSPECT}")
	chmod 600 "${BASE_DIR}/config/ds.env" || return 1
	enable_document_server_env_file "${DS_COMPOSE_FILE}" || return 1
	local CONFIG EXISTING_ID
	CONFIG=$(compose_with_document_server_mounts -f "${DS_COMPOSE_FILE}" config --format json) || return 1
	DS_NEW_CONTAINER_NAME=$(jq -er '.services["onlyoffice-document-server"].container_name' <<<"${CONFIG}") || return 1
	COMPOSE_PROJECT_NAME=$(jq -er '.name' <<<"${CONFIG}") || return 1
	EXISTING_ID=$(docker inspect --format '{{.Id}}' "${DS_NEW_CONTAINER_NAME}" 2>/dev/null) || EXISTING_ID=""
	[ -z "${EXISTING_ID}" ] || [ "${EXISTING_ID}" = "${DS_ORIGINAL_ID}" ] || {
		echo "Target Docs container ${DS_NEW_CONTAINER_NAME} already exists; aborting adoption." >&2
		return 1
	}
	# Driver-backed volumes may unmount when Docs stops. Do not mistake their
	# empty host mountpoint for the data to copy. Additional mounts can reuse
	# those volumes directly, but managed data needs an explicit migration.
	local VOLUME_INFO VOLUME_NAME
	while IFS= read -r VOLUME_NAME; do
		VOLUME_INFO=$(docker volume inspect "${VOLUME_NAME}") || return 1
		jq -e '.[0] | .Driver == "local" and ((.Options // {}) | length == 0)' <<<"${VOLUME_INFO}" >/dev/null || {
			echo "Managed Docs volume ${VOLUME_NAME} uses driver options; migrate its data explicitly before adoption." >&2
			return 1
		}
	done < <(jq -r '.[] | select(.managed != null and .type == "volume") | .source' <<<"${DS_MOUNT_PLAN}")
	docker stop "${DS_ORIGINAL_ID}" >/dev/null || return 1

	local MOUNT TYPE SRC SUBPATH NAME DEST_SUBDIR SOURCE_PATH TARGET_PATH
	while IFS= read -r MOUNT; do
		TYPE=$(jq -r '.type' <<<"${MOUNT}")
		SRC=$(jq -r '.source' <<<"${MOUNT}")
		SUBPATH=$(jq -r '.subpath // empty' <<<"${MOUNT}")
		NAME=$(jq -r '.managed' <<<"${MOUNT}")
		DEST_SUBDIR=$(jq -r '.subdir' <<<"${MOUNT}")
		if [ "${TYPE}" = volume ]; then
			SOURCE_PATH=$(docker volume inspect --format '{{.Mountpoint}}' "${SRC}") || return 1
			[ -z "${SUBPATH}" ] || SOURCE_PATH+="/${SUBPATH}"
		else
			SOURCE_PATH="${SRC}"
		fi
		[ -d "${SOURCE_PATH}" ] || { echo "Docs data directory is inaccessible: ${SOURCE_PATH}" >&2; return 1; }
		TARGET_PATH=$(resolve_ds_volume_path "${NAME}") || return 1
		if [ -n "${DEST_SUBDIR}" ]; then
			TARGET_PATH+="/${DEST_SUBDIR}"
			mkdir -p -- "${TARGET_PATH}" || return 1
		fi
		[ "${SOURCE_PATH}" -ef "${TARGET_PATH}" ] && continue
		SOURCE_PATH=$(readlink -f "${SOURCE_PATH}") || return 1
		TARGET_PATH=$(readlink -f "${TARGET_PATH}") || return 1
		case "${TARGET_PATH}/" in "${SOURCE_PATH}/"*) echo "Docs migration target is inside its source: ${TARGET_PATH}" >&2; return 1 ;; esac
		cp -a -- "${SOURCE_PATH}/." "${TARGET_PATH}/" || {
			echo "Failed to copy Docs data from ${SOURCE_PATH}; keeping the original container." >&2
			return 1
		}
	done < <(jq -c '[.[] | select(.managed != null)] | sort_by(.target | length)[]' <<<"${DS_MOUNT_PLAN}")


	if [ "${DS_NEW_CONTAINER_NAME}" = "${DS_ORIGINAL_NAME}" ]; then
		docker rename "${DS_ORIGINAL_ID}" "${DS_ORIGINAL_NAME}-apps-migration-backup" || return 1
		DS_ORIGINAL_RENAMED=true
	fi
	if [ "${DEPLOYMENT_MODE}" != standalone ]; then
		echo "Docs RabbitMQ/Redis storage is retained on Docs; it is not imported into the external services."
	fi
	return 0
}

# Keep the original container until the replacement has its mounts and is healthy.
finish_document_server_migration () {
	[ "${DS_ADOPTION_ACTIVE}" = true ] || return 0
	local INSPECT STATUS DEADLINE=$((SECONDS + 600))
	while [ "${SECONDS}" -lt "${DEADLINE}" ]; do
		INSPECT=$(docker inspect --type container "${DS_NEW_CONTAINER_NAME}") || return 1
		STATUS=$(jq -r '.[0] | if .State.Running then (.State.Health.Status // "missing-healthcheck") else "stopped" end' <<<"${INSPECT}")
		case "${STATUS}" in
			healthy | missing-healthcheck) break ;;
			starting) sleep 5 ;;
			*) echo "Replacement Docs is ${STATUS}; keeping the original container." >&2; return 1 ;;
		esac
	done
	case "${STATUS}" in
		healthy | missing-healthcheck) ;;
		*) echo "Timed out waiting for replacement Docs." >&2; return 1 ;;
	esac
	# Match sources by volume name (including anonymous names), not host mountpoints.
	jq -e --argjson plan "${DS_MOUNT_PLAN}" '
		.[0] as $container | .[0].Mounts as $actual |
		all($plan[] | select(.managed == null);
			. as $expected | any($actual[];
				.Type == $expected.type and .Destination == $expected.target and
				.RW == ($expected.read_only | not) and
				(if .Type == "volume" then .Name else .Source end) == $expected.source and
				(if .Type == "bind" then
					(.Propagation // "rprivate") == $expected.propagation and
					($expected.selinux == null or ((.Mode // "" | split(",")) | index($expected.selinux) != null))
				 else
					([$container.HostConfig.Mounts[]? | select(.Target == $expected.target)][0].VolumeOptions.Subpath // null) == $expected.subpath
				 end)))
	' <<<"${INSPECT}" >/dev/null || { echo "Replacement Docs mount verification failed." >&2; return 1; }
	docker rm "${DS_ORIGINAL_ID}" >/dev/null || return 1
	DS_ADOPTION_ACTIVE=false
	trap - EXIT
	[ -z "${DS_PREVIOUS_EXIT_TRAP}" ] || eval "${DS_PREVIOUS_EXIT_TRAP}"
}

# Remove inherited Docs HTTPS only after the new front end accepts it.
strip_inherited_https_from_document_server () {
	local APP_DATA_PATH
	APP_DATA_PATH=$(resolve_ds_volume_path app_data) || return 1
	[ -n "${APP_DATA_PATH}" ] || return 1
	rm -rf -- "${APP_DATA_PATH}/certs" || return 1

	local DS_COMPOSE_FILE="${BASE_DIR}/ds.yml"
	[ "${DEPLOYMENT_MODE}" = "standalone" ] && DS_COMPOSE_FILE="${BASE_DIR}/docker-compose.yml"
	[ -f "${BASE_DIR}/config/ds.env" ] && sed -i -E '/^(SSL_CERTIFICATE_PATH|SSL_KEY_PATH|SSL_DHPARAM_PATH|CA_CERTIFICATES_PATH|SSL_VERIFY_CLIENT)=/d' "${BASE_DIR}/config/ds.env"
	# Recreate to apply the edited env_file; restart keeps the old SSL env.
	compose_with_document_server_mounts -f "${DS_COMPOSE_FILE}" up -d --force-recreate onlyoffice-document-server || {
		echo "Warning: failed to recreate the Document Server after stripping its HTTPS config; the old SSL environment may still be active." >&2
		return 1
	}
}

# Complete inherited HTTPS handoff after cert setup.
finish_https_takeover () {
	if [ "$1" -eq 0 ]; then
		[ "${DS_HTTPS_INHERITED}" = "true" ] && strip_inherited_https_from_document_server
	elif [ "${DS_HTTPS_INHERITED}" = "true" ]; then
		echo "Warning: failed to set up HTTPS for ${PRODUCT_NAME} for ${APP_DOMAIN_PORTAL}, inherited from the migrated Document Server; HTTPS is not reachable until this is resolved manually." >&2
	fi
}

install_document_server () {
	reconfigure DOCUMENT_SERVER_JWT_HEADER "${DOCUMENT_SERVER_JWT_HEADER}"
	reconfigure DOCUMENT_SERVER_JWT_SECRET "${DOCUMENT_SERVER_JWT_SECRET}"
	enable_document_server_env_file "${BASE_DIR}/ds.yml"
	if [ "$INSTALL_DOCUMENT_SERVER" == "pull" ]; then
		compose_with_document_server_mounts -f "${BASE_DIR}/ds.yml" pull
	elif [ "${DOCUMENT_SERVER_ATTACHED}" = "true" ]; then
		migrate_document_server_data || { echo "Aborting: failed to migrate the existing Document Server's data." >&2; exit 1; }
		compose_with_document_server_mounts -f "${BASE_DIR}/ds.yml" up -d || exit 1
		finish_document_server_migration || exit 1
	elif [[ -z ${DOCUMENT_SERVER_HOST} ]] && [ "$INSTALL_DOCUMENT_SERVER" == "true" ]; then
		compose_with_document_server_mounts -f "${BASE_DIR}/ds.yml" up -d
	fi
}
