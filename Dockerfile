# syntax=docker/dockerfile:1
#
# Builds a PNETLAB-ready FRR image from an upstream quay.io/frrouting/frr
# image by enabling the requested daemons and vtysh. See build.sh.

ARG FRR_IMAGE=quay.io/frrouting/frr:10.7.0
FROM ${FRR_IMAGE}

# Space-separated list of daemon names to flip from "=no" to "=yes" in
# /etc/frr/daemons. Populated by build.sh from daemons-all.txt (or an
# override) at build time.
ARG DAEMONS

RUN set -eu; \
    if [ -z "${DAEMONS}" ]; then \
        echo "ERROR: DAEMONS build-arg is empty" >&2; exit 1; \
    fi; \
    for d in ${DAEMONS}; do \
        if grep -q "^${d}=no$" /etc/frr/daemons; then \
            sed -i "s/^${d}=no$/${d}=yes/" /etc/frr/daemons; \
        else \
            echo "WARNING: '${d}=no' not found in /etc/frr/daemons (already enabled, always-on, or misspelled) - skipping" >&2; \
        fi; \
    done; \
    sed -i 's/^vtysh_enable=no$/vtysh_enable=yes/' /etc/frr/daemons; \
    grep -q '^vtysh_enable=yes$' /etc/frr/daemons; \
    [ -f /etc/frr/vtysh.conf ] || install -o frr -g frrvty -m 0640 /dev/null /etc/frr/vtysh.conf; \
    echo "---- resulting /etc/frr/daemons ----"; \
    grep -E '^[a-z0-9_]+=(yes|no)$' /etc/frr/daemons

# PNETLAB's docker node type attaches the console via
# `docker exec -it <container> /bin/bash`, which sources ~/.bashrc for
# root. Auto-start vtysh there so consoling in drops straight into the
# FRR CLI instead of a plain shell. Not exec'd - vtysh runs as a normal
# foreground command, so "exit" from vtysh falls back to bash instead of
# just disconnecting, in case a raw shell is ever needed.
RUN printf '%s\n' \
    'if [ -t 0 ] && [ -z "${VTYSH_AUTOSTART:-}" ]; then' \
    '    export VTYSH_AUTOSTART=1' \
    '    vtysh' \
    'fi' \
    >> /root/.bashrc
