#!/usr/bin/env bash
# Note: Avoid usage of arrays as MacOS users have an older version of bash (v3.x) which does not supports arrays
set -eu

DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

BUILD_OPTS="$*"
FORCE=0

# Allow user to override docker command
DOCKER=${DOCKER:-docker}

# Ensure that default docker command is not set up in rootless mode
if \
  ! ${DOCKER} ps    >/dev/null 2>&1 || \
    ${DOCKER} info 2>/dev/null | grep -q rootless \
; then
	DOCKER="sudo ${DOCKER}"
fi
if ! ${DOCKER} ps >/dev/null; then
	echo "error connecting to docker:"
	${DOCKER} ps
	exit 1
fi

CONFIG_FILE=""
if [ -f "${DIR}/config" ]; then
	CONFIG_FILE="${DIR}/config"
fi

# IMG_CHANNEL selects the apt channel the image builds from and follows:
#   stable  (default) — production suite only (trixie)
#   testing (--pre)   — adds the pre-release suite (trixie-testing) at build
#                       time AND ships it in the image, so flashed devices
#                       keep tracking pre-release packages over OTA.
IMG_CHANNEL="${IMG_CHANNEL:-stable}"

# Handle long options before getopts (getopts does not support them)
for arg in "$@"; do
	if [ "$arg" = "--force" ]; then
		FORCE=1
	fi
	if [ "$arg" = "--pre" ]; then
		IMG_CHANNEL="testing"
	fi
done

if [ "${IMG_CHANNEL}" != "stable" ] && [ "${IMG_CHANNEL}" != "testing" ]; then
	echo "IMG_CHANNEL must be 'stable' or 'testing' (got '${IMG_CHANNEL}')" 1>&2
	exit 1
fi

while getopts ":c:f" flag
do
	case "${flag}" in
		c)
			CONFIG_FILE="${OPTARG}"
			;;
		f)
			FORCE=1
			;;
		\?)
			# Silently ignore unknown options (long options like --pre, --force
			# are handled above before getopts, but still appear in $@)
			;;
	esac
done

# Ensure that the configuration file is an absolute path
if test -x /usr/bin/realpath; then
	CONFIG_FILE=$(realpath -s "$CONFIG_FILE" || realpath "$CONFIG_FILE")
fi

# Ensure that the confguration file is present
if test -z "${CONFIG_FILE}"; then
	echo "Configuration file need to be present in '${DIR}/config' or path passed as parameter"
	exit 1
else
	# shellcheck disable=SC1090
	source ${CONFIG_FILE}
fi

# Pull in APT_REPO_URL and friends for use below (PassThroughPattern, etc.)
# shellcheck disable=SC1091
source "${DIR}/config.sh"

CONTAINER_NAME=${CONTAINER_NAME:-pigen_work}
CONTINUE=${CONTINUE:-0}
PRESERVE_CONTAINER=${PRESERVE_CONTAINER:-0}
PIGEN_DOCKER_OPTS=${PIGEN_DOCKER_OPTS:-""}

IMG_DATE="$(date +%Y-%m-%d)"

# When IMG_VERSION is set (CI release builds), name the image
# pistompOS-<version>.img instead of the default <date>-pistompOS.img.
# IMG_FILENAME is honoured by pi-gen's build.sh and is not set in `config`,
# so passing it as an env var into the container takes effect cleanly.
IMG_VERSION="${IMG_VERSION:-}"
IMG_FILENAME_ENV=""
if [ -n "${IMG_VERSION}" ]; then
	IMG_FILENAME_ENV="-e IMG_FILENAME=${IMG_NAME}-${IMG_VERSION}"
elif [ "${IMG_CHANNEL}" = "testing" ]; then
	# No explicit version (local --pre build): mark the default date-based
	# name so a testing image is never mistaken for a production one.
	IMG_FILENAME_ENV="-e IMG_FILENAME=${IMG_DATE}-${IMG_NAME}-pre"
fi

# --- apt-cacher-ng (persistent package cache) ---
APT_CACHER_CONTAINER="pigen_apt_cacher"
APT_CACHER_NET="pigen_net"
APT_CACHER_IMAGE="sameersbn/apt-cacher-ng:latest"
APT_CACHER_DIR="${DIR}/cache/apt-cacher"
APT_PROXY="http://${APT_CACHER_CONTAINER}:3142"

start_apt_cache() {
  mkdir -p "${APT_CACHER_DIR}"
  # Purge rsync metadata snapshots — these are rebuilt on startup and left
  # corrupt after a crash, causing apt-cacher-ng to exit immediately.
  rm -rf "${APT_CACHER_DIR}/_xstore/rsnap"
  ${DOCKER} network create ${APT_CACHER_NET} 2>/dev/null || true
  ${DOCKER} rm -f ${APT_CACHER_CONTAINER} 2>/dev/null || true
  # Derive hostname from APT_REPO_URL for PassThroughPattern so our custom
  # apt repo's Packages index is always fetched live, never served stale from cache.
  APT_REPO_HOST=$(echo "${APT_REPO_URL}" | sed 's|https\?://||; s|/.*||')
  ${DOCKER} run -d \
    --name ${APT_CACHER_CONTAINER} \
    --network ${APT_CACHER_NET} \
    --health-cmd='wget -q -O /dev/null http://localhost:3142/acng-report.html || exit 1' \
    --health-interval=1s \
    --health-retries=10 \
    --volume "${APT_CACHER_DIR}":/var/cache/apt-cacher-ng \
    -e "ACNG_PassThroughPattern=.*${APT_REPO_HOST}.*" \
    ${APT_CACHER_IMAGE}
  echo "Waiting for apt-cacher-ng to become healthy..."
  for i in $(seq 1 15); do
    if ${DOCKER} inspect --format='{{.State.Health.Status}}' ${APT_CACHER_CONTAINER} 2>/dev/null | grep -q healthy; then
      echo "apt-cacher-ng is ready."
      return 0
    fi
    sleep 1
  done
  echo "ERROR: apt-cacher-ng did not become healthy within 15s." >&2
  echo "       The build sets APT_PROXY=${APT_PROXY}; continuing would point apt" >&2
  echo "       at a dead proxy and fail mid-build. Check: docker logs ${APT_CACHER_CONTAINER}" >&2
  return 1
}

stop_apt_cache() {
  ${DOCKER} rm -f ${APT_CACHER_CONTAINER} 2>/dev/null || true
  ${DOCKER} network rm ${APT_CACHER_NET} 2>/dev/null || true
}

if [ -z "${IMG_NAME}" ]; then
	echo "IMG_NAME not set in 'config'" 1>&2
	echo 1>&2
exit 1
fi

# Ensure the Git Hash is recorded before entering the docker container.
# Both are computed on the host so the image build needs no .git copied in
# (see .dockerignore — the whole .git is excluded from the build context).
GIT_HASH=${GIT_HASH:-"$(git rev-parse HEAD)"}
GIT_DESCRIBE=${GIT_DESCRIBE:-"$(git describe --dirty='*' --always)"}

CONTAINER_EXISTS=$(${DOCKER} ps -a --filter name="${CONTAINER_NAME}" -q)
CONTAINER_RUNNING=$(${DOCKER} ps --filter name="${CONTAINER_NAME}" -q)
if [ "${CONTAINER_RUNNING}" != "" ]; then
	echo "The build is already running in container ${CONTAINER_NAME}. Aborting."
	exit 1
fi
if [ "${FORCE}" = "1" ]; then
	if [ "${CONTAINER_EXISTS}" != "" ]; then
		echo "Removing existing container ${CONTAINER_NAME}..."
		${DOCKER} rm -v "${CONTAINER_NAME}"
		CONTAINER_EXISTS=""
	fi
	# echo "Clearing deploy/..."
	# rm -rf "${DIR}/deploy"/*
elif [ "${CONTAINER_EXISTS}" != "" ] && [ "${CONTINUE}" != "1" ]; then
	echo "Container ${CONTAINER_NAME} already exists and you did not specify CONTINUE=1. Aborting."
	echo "You can delete the existing container like this:"
	echo "  ${DOCKER} rm -v ${CONTAINER_NAME}"
	exit 1
fi

# Modify original build-options to allow config file to be mounted in the docker container
BUILD_OPTS="$(echo "${BUILD_OPTS:-}" | sed -E 's@-c ?([^ ]+)@-c /config@; s/--force//g; s/--pre//g; s/(^| )-f( |$)/ /g')"

# Local .deb overrides live in overrides/ (produced by build-package-docker.sh).
mkdir -p "${DIR}/overrides"

# Prerelease leak guard: a '~' in a Debian version marks a pre-release
# (channel: trixie-testing). A stable build must NEVER install one, including
# via local overrides — fail instead of silently shipping it to production.
if [ "${IMG_CHANNEL}" != "testing" ] && ls "${DIR}/overrides"/*~*.deb >/dev/null 2>&1; then
  echo "ERROR: overrides/ contains pre-release packages (version has '~'):" 1>&2
  ls "${DIR}/overrides"/*~*.deb 1>&2
  echo "       Pass --pre to build a testing-channel image, or remove them." 1>&2
  exit 1
fi

# If there are no local .deb overrides, remove any stale cache/apt-repo/ left
# from a previous build-package-docker.sh run.  Without this, apt silently
# installs old versions from the leftover repo instead of fetching from the
# published apt repo.
if ! ls "${DIR}/overrides"/*.deb >/dev/null 2>&1; then
  if [ -d "${DIR}/cache/apt-repo" ]; then
    echo "==> No local .deb overrides; removing stale cache/apt-repo/..."
    rm -rf "${DIR}/cache/apt-repo"
  fi
fi

# Pre-flight: verify every custom package is available before spending time on
# the Docker build.  Checks overrides/ AND the published apt repo (both suites
# when IMG_CHANNEL=testing).
OVERRIDES_DIR="${DIR}/overrides" IMG_CHANNEL="${IMG_CHANNEL}" \
  bash "${DIR}/scripts/check-packages.sh"

${DOCKER} build --build-arg BASE_IMAGE=debian:trixie -t pi-gen "${DIR}"

if [ "${CONTAINER_EXISTS}" != "" ]; then
  DOCKER_CMDLINE_NAME="${CONTAINER_NAME}_cont"
  DOCKER_CMDLINE_PRE="--rm"
  DOCKER_CMDLINE_POST="--volumes-from=${CONTAINER_NAME}"
else
  DOCKER_CMDLINE_NAME="${CONTAINER_NAME}"
  DOCKER_CMDLINE_PRE=""
  DOCKER_CMDLINE_POST=""
fi

# Check if binfmt_misc is required
binfmt_misc_required=1
case $(uname -m) in
  aarch64)
    binfmt_misc_required=0
    ;;
  arm*)
    binfmt_misc_required=0
    ;;
esac

# Check if qemu-aarch64-static and /proc/sys/fs/binfmt_misc are present
if [[ "${binfmt_misc_required}" == "1" ]]; then
  if ! qemu_arm=$(which qemu-aarch64-static) ; then
    echo "qemu-aarch64-static not found (please install qemu-user-static)"
    exit 1
  fi
  if [ ! -f /proc/sys/fs/binfmt_misc/register ]; then
    echo "binfmt_misc required but not mounted, trying to mount it..."
    if ! mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc ; then
        echo "mounting binfmt_misc failed"
        exit 1
    fi
    echo "binfmt_misc mounted"
  fi
  if ! grep -q "^interpreter ${qemu_arm}" /proc/sys/fs/binfmt_misc/qemu-aarch64* ; then
    # Register qemu-aarch64 for binfmt_misc
    reg="echo ':qemu-aarch64-rpi:M::"\
"\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7\x00:"\
"\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:"\
"${qemu_arm}:F' > /proc/sys/fs/binfmt_misc/register"
    echo "Registering qemu-aarch64 for binfmt_misc..."
    sudo bash -c "${reg}" 2>/dev/null || true
  fi
fi

trap '
  echo "got CTRL+C... please wait 5s"
  ${DOCKER} stop -t 5 ${DOCKER_CMDLINE_NAME}
  stop_apt_cache
' SIGINT SIGTERM

start_apt_cache

time ${DOCKER} run \
  $DOCKER_CMDLINE_PRE \
  --name "${DOCKER_CMDLINE_NAME}" \
  --privileged \
  --network ${APT_CACHER_NET} \
  ${PIGEN_DOCKER_OPTS} \
  --volume "${CONFIG_FILE}":/config:ro \
  --volume "${DIR}/cache":/pistomp-cache:rw \
  --volume "${DIR}/overrides":/pistomp-overrides:ro \
  ${IMG_FILENAME_ENV} \
  -e "IMG_CHANNEL=${IMG_CHANNEL}" \
  -e "GIT_HASH=${GIT_HASH}" \
  -e "GIT_DESCRIBE=${GIT_DESCRIBE}" \
  -e "APT_PROXY=${APT_PROXY}" \
  -e "UV_CACHE_DIR=/pistomp-cache/uv-cache" \
  -e "UV_PYTHON_INSTALL_DIR=/pistomp-cache/uv-python" \
  -e "PIP_CACHE_DIR=/pistomp-cache/pip-cache" \
  $DOCKER_CMDLINE_POST \
  pi-gen \
  bash -e -o pipefail -c "
    dpkg-reconfigure qemu-user-binfmt &&
    # binfmt_misc is sometimes not mounted with debian trixie image
    (mount binfmt_misc -t binfmt_misc /proc/sys/fs/binfmt_misc || true) &&
    cd /pi-gen &&
    echo '==> Downloading non-.deb assets...' &&
    CACHE_DIR=/pistomp-cache bash scripts/fetch-assets.sh &&
    if ls /pistomp-overrides/*.deb >/dev/null 2>&1; then
      echo '==> Building local apt override repository from overrides/...' &&
      OVERRIDES_DIR=/pistomp-overrides REPO_DIR=/pistomp-cache/apt-repo bash scripts/setup-apt-repo.sh
    fi &&
    ./build.sh ${BUILD_OPTS} &&
    rsync -av work/*/build.log "deploy/${IMG_DATE}-build.log"
  " &
  wait "$!"

stop_apt_cache

# Ensure that deploy/ is always owned by calling user
echo "copying results from deploy/"
${DOCKER} cp "${CONTAINER_NAME}":/pi-gen/deploy - | tar -xf -

echo "copying log from container ${CONTAINER_NAME} to deploy/"
${DOCKER} logs --timestamps "${CONTAINER_NAME}" &>"deploy/${IMG_DATE}-build-docker.log"

ls -lah deploy

# Assert the image actually got the package versions the pre-flight resolved
bash "${DIR}/scripts/verify-image-packages.sh"

# cleanup
if [ "${PRESERVE_CONTAINER}" != "1" ]; then
	${DOCKER} rm -v "${CONTAINER_NAME}"
fi

echo "Done! Your image(s) should be in deploy/"
