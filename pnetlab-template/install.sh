#!/usr/bin/env bash
#
# Installs the FRRouting PNETLAB docker node template.
#
# PNETLAB auto-discovers node templates by scanning
# /opt/unetlab/html/templates/<platform>/*.yml (platform is "intel" or
# "amd", chosen by /opt/unetlab/html/includes/init.php based on
# /opt/unetlab/platform). A template only appears enabled in the "Add a
# node" dialog if a locally present docker image name contains the
# template's filename (see getTemplates() in
# /opt/unetlab/html/includes/functions.php) - so this template shows up
# automatically once any image tag containing "frrouting" exists, e.g.
# the ones produced by ../build.sh.
#
# This installs to both "intel" and "amd" platform dirs (harmless if one
# doesn't apply to this host) plus the "device" dir, which holds the
# node-edit-parameter form layout consumed by the web UI.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PNETLAB_TPL_DIR="/opt/unetlab/html/templates"

if [ ! -d "${PNETLAB_TPL_DIR}" ]; then
    echo "ERROR: ${PNETLAB_TPL_DIR} not found - is this a PNETLAB host?" >&2
    exit 1
fi

for dir in intel amd device; do
    src="${SCRIPT_DIR}/${dir}/frrouting.yml"
    dst="${PNETLAB_TPL_DIR}/${dir}/frrouting.yml"
    if [ ! -d "${PNETLAB_TPL_DIR}/${dir}" ]; then
        echo "Skipping ${dir} (no ${PNETLAB_TPL_DIR}/${dir} on this host)"
        continue
    fi
    install -o www-data -g www-data -m 0755 "${src}" "${dst}"
    echo "Installed ${dst}"
done

echo
echo "Done. The 'FRRouting' node type will appear in the Add Node dialog"
echo "as soon as a local docker image tag containing 'frrouting' exists"
echo "(build one with ../build.sh)."
