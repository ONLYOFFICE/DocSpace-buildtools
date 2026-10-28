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


# Creates a swap file; any failure only produces a warning, swap is optional
make_swap () {
	local SWAPFILE="$1"
	local DISK_REQUIREMENTS=6144 #6Gb free space
	local AVAILABLE_DISK_SPACE EXIST

	AVAILABLE_DISK_SPACE=$(df -Pm / | awk 'NR == 2 { print $4 }')
	EXIST=$(swapon -s | awk '{ print $1 }' | { grep -x "${SWAPFILE}" || true; })

	if [ -n "${EXIST}" ]; then
		return 0
	fi

	if [ "${AVAILABLE_DISK_SPACE}" -le "${DISK_REQUIREMENTS}" ]; then
		echo "Warning: swap file was not created, less than ${DISK_REQUIREMENTS} MB of free disk space on /"
		return 0
	fi

	# fallocate may produce a file with holes that swapon rejects, so fall back to dd
	if enable_swap_file "${SWAPFILE}" fallocate || enable_swap_file "${SWAPFILE}" dd; then
		awk -v swapfile="${SWAPFILE}" '$1 == swapfile && $3 == "swap" { found = 1 } END { exit !found }' /etc/fstab || echo "${SWAPFILE} none swap sw 0 0" >> /etc/fstab
		echo "Swap file ${SWAPFILE} (6 GB) was created and enabled"
	else
		rm -f "${SWAPFILE}"
		echo "Warning: swap file was not created, continuing without it"
	fi
	return 0
}

enable_swap_file () {
	local SWAPFILE="$1"
	local METHOD="$2"

	rm -f "${SWAPFILE}" && touch "${SWAPFILE}" || return 1
	[ "$(df -T / | awk 'NR==2{print $2}')" != "btrfs" ] || chattr +C "${SWAPFILE}" || return 1

	if [ "${METHOD}" = "fallocate" ]; then
		fallocate -l 6G "${SWAPFILE}"
	else
		dd if=/dev/zero of="${SWAPFILE}" bs=1MiB count=6144 status=none
	fi || return 1

	chmod 600 "${SWAPFILE}" && mkswap "${SWAPFILE}" >/dev/null && swapon "${SWAPFILE}"
}

# Disables and deletes the given swap files and drops their /etc/fstab entries
remove_swap () {
	local SWAPFILE

	for SWAPFILE in "$@"; do
		if swapon --show=NAME --noheadings | grep -qx "${SWAPFILE}"; then
			swapoff "${SWAPFILE}" || echo "Warning: failed to disable ${SWAPFILE}"
		fi
		rm -f "${SWAPFILE}"
		[ ! -f /etc/fstab ] || sed -i "\|^${SWAPFILE}[[:space:]]\+none[[:space:]]\+swap[[:space:]]|d" /etc/fstab
	done
	return 0
}
