#!/usr/bin/env bash
#
# Build a PNETLAB-ready FRR docker image: pulls an upstream
# quay.io/frrouting/frr image, enables the requested daemons + vtysh via
# Dockerfile, and tags the result for use as a PNETLAB docker node
# template image.
#
# Usage:
#   ./build.sh <tag_or_ref> [options]
#
# <tag_or_ref> is either a bare version like "10.7.0" (assumed to be
# quay.io/frrouting/frr:10.7.0) or a full image reference like
# "quay.io/frrouting/frr:10.7.0".
#
# Options:
#   -d, --daemons "bgpd ospfd ..."   Space/comma-separated daemon list to
#                                    enable. Overrides --daemons-file.
#   -f, --daemons-file PATH          File with one daemon name per line
#                                    (# comments and blank lines ignored).
#                                    Default: daemons-all.txt (all daemons).
#   -o, --tag NAME                   Local image tag to produce.
#                                    Default: frrouting:<version>
#       --list-daemons               Print the known valid daemon names
#                                    and exit.
#       --no-pull                    Skip "docker pull" of the upstream
#                                    image (use whatever is cached locally).
#       --dry-run                    Print what would be done, don't touch
#                                    docker.
#   -h, --help                       Show this help.
#
# Examples:
#   ./build.sh 10.7.0
#   ./build.sh quay.io/frrouting/frr:10.7.0
#   ./build.sh 10.7.0 --daemons "bgpd ospfd isisd"
#   ./build.sh 10.7.0 -o frrouting-lab:10.7.0

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REGISTRY_REPO="quay.io/frrouting/frr"
DEFAULT_DAEMONS_FILE="${SCRIPT_DIR}/daemons-all.txt"
KNOWN_DAEMONS_FILE="${SCRIPT_DIR}/daemons-all.txt"

usage() {
    sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

IMAGE_REF=""
DAEMONS_OVERRIDE=""
DAEMONS_FILE="${DEFAULT_DAEMONS_FILE}"
LOCAL_TAG=""
DO_PULL=1
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        -d|--daemons)
            DAEMONS_OVERRIDE="$2"; shift 2 ;;
        -f|--daemons-file)
            DAEMONS_FILE="$2"; shift 2 ;;
        -o|--tag)
            LOCAL_TAG="$2"; shift 2 ;;
        --list-daemons)
            grep -vE '^\s*(#|$)' "${KNOWN_DAEMONS_FILE}"; exit 0 ;;
        --no-pull)
            DO_PULL=0; shift ;;
        --dry-run)
            DRY_RUN=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)
            if [ -n "${IMAGE_REF}" ]; then
                echo "Unexpected extra argument: $1" >&2; exit 1
            fi
            IMAGE_REF="$1"; shift ;;
    esac
done

if [ -z "${IMAGE_REF}" ]; then
    echo "ERROR: missing <tag_or_ref> argument" >&2
    usage >&2
    exit 1
fi

# Resolve short tag ("10.7.0") vs full reference (contains a "/").
case "${IMAGE_REF}" in
    */*) FULL_REF="${IMAGE_REF}" ;;
    *)   FULL_REF="${DEFAULT_REGISTRY_REPO}:${IMAGE_REF}" ;;
esac

VERSION="${FULL_REF##*:}"
LOCAL_TAG="${LOCAL_TAG:-frrouting:${VERSION}}"

# Build the daemon list.
if [ -n "${DAEMONS_OVERRIDE}" ]; then
    DAEMONS=$(echo "${DAEMONS_OVERRIDE}" | tr ',' ' ')
else
    if [ ! -f "${DAEMONS_FILE}" ]; then
        echo "ERROR: daemons file not found: ${DAEMONS_FILE}" >&2
        exit 1
    fi
    DAEMONS=$(grep -vE '^\s*(#|$)' "${DAEMONS_FILE}" | tr '\n' ' ')
fi
DAEMONS=$(echo "${DAEMONS}" | xargs)   # trim/collapse whitespace

if [ -z "${DAEMONS}" ]; then
    echo "ERROR: resolved daemon list is empty" >&2
    exit 1
fi

# Validate against the known daemon list to catch typos early.
KNOWN_DAEMONS=$(grep -vE '^\s*(#|$)' "${KNOWN_DAEMONS_FILE}")
UNKNOWN=""
for d in ${DAEMONS}; do
    if ! grep -qx "${d}" <<< "${KNOWN_DAEMONS}"; then
        UNKNOWN="${UNKNOWN} ${d}"
    fi
done
if [ -n "${UNKNOWN}" ]; then
    echo "ERROR: unknown daemon name(s):${UNKNOWN}" >&2
    echo "Run '${0} --list-daemons' to see valid names." >&2
    exit 1
fi

echo "Upstream image : ${FULL_REF}"
echo "Local tag      : ${LOCAL_TAG}"
echo "Daemons enabled: ${DAEMONS}"

if [ "${DRY_RUN}" = "1" ]; then
    echo "(dry run, stopping here)"
    exit 0
fi

if [ "${DO_PULL}" = "1" ]; then
    docker pull "${FULL_REF}"
fi

docker build \
    --build-arg FRR_IMAGE="${FULL_REF}" \
    --build-arg DAEMONS="${DAEMONS}" \
    -t "${LOCAL_TAG}" \
    -f "${SCRIPT_DIR}/Dockerfile" \
    "${SCRIPT_DIR}"

echo
echo "Built ${LOCAL_TAG} from ${FULL_REF}."
echo "It will show up in 'docker image ls' and can be referenced by tag in a PNETLAB docker node template."
