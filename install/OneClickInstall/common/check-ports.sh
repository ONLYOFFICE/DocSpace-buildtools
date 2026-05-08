#!/bin/bash

set -e

cat<<EOF

#######################################
#  CHECK PORTS
#######################################

EOF

PRODUCT_INSTALLED="false"
DOCUMENT_SERVER_INSTALLED="false"

if command -v dpkg >/dev/null 2>&1; then
	PKG_LIST="$(dpkg -l)"
elif command -v rpm >/dev/null 2>&1; then
	PKG_LIST="$(rpm -qa)"
fi

if grep -q "${product}" <<< "$PKG_LIST"; then
	echo "${product} $RES_APP_INSTALLED"
	PRODUCT_INSTALLED="true"
fi

if grep -q "${package_sysname}-documentserver" <<< "$PKG_LIST"; then
	echo "${package_sysname}-documentserver $RES_APP_INSTALLED"
	DOCUMENT_SERVER_INSTALLED="true"
fi

if [ "$PRODUCT_INSTALLED" = "true" ] && [ "$UPDATE" != "true" ]; then
	echo "${product} is already installed. Use --update true to update."
	exit 0
fi

if [ "$UPDATE" != "true" ]; then
	PRODUCT_PORTS=(
		"${APP_PORT:-80}" 5000 5001 5003 5004 5005 5006 5007 5009 5010 5011 5012 5013 5014 5015
		5027 5032 5033 5034 5075 5099 5100 5124 5157 5158
		8080 8081 8092 9090 9834 9899
	)

	DEPENDENCY_PORTS=(
		"${MYSQL_SERVER_PORT:-3306}"
		"${ELK_PORT:-9200}"
	)

	if [ "$DOCUMENT_SERVER_INSTALLED" != "true" ]; then
		DEPENDENCY_PORTS+=(
			"${DS_PORT:-8083}" 8000 5432
			"${RABBITMQ_PORT:-5672}" "${REDIS_PORT:-6379}"
		)
	fi

	[ "${INSTALL_FLUENT_BIT}" = "true" ] && DEPENDENCY_PORTS+=(5601)

	USED_PORTS=""
	for PORT in $(printf "%s\n" "${PRODUCT_PORTS[@]}" "${DEPENDENCY_PORTS[@]}" | sort -n -u); do
		[[ "$PORT" =~ ^[0-9]+$ ]] || continue
		if ss -H -lnt | awk '{print $4}' | grep -qE ":${PORT}$"; then
			USED_PORTS="${USED_PORTS}${USED_PORTS:+, }${PORT}"
		fi
	done

	if [ -n "$USED_PORTS" ]; then
		echo "The following TCP ports are already in use: $USED_PORTS"
		echo "$RES_CHECK_PORTS"
		exit 1
	fi
fi
