#!/bin/bash
# Builds PREEMPT_RT kernel .deb packages for Raspberry Pi arm64 and caches
# them in stage2/05-pistomp/files/sys/ for consumption by build-docker.sh.
#
# Mirror of pistomp-arch's build-rt-kernel-docker.sh but produces .deb files
# via cross-compilation (x86_64 Debian trixie → arm64) rather than makepkg.
#
# Run this once before ./build-docker.sh; subsequent image builds reuse the
# cached .deb files and skip the 20-40 minute compile step.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source version pins from config.sh (single source of truth)
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

# Full kernel release string used by the bootloader and .deb file names
KERNEL_RELEASE="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"

CACHE_DIR="${SCRIPT_DIR}/stage2/05-pistomp/files/sys"
SOURCE_CACHE_DIR="${SCRIPT_DIR}/.kernel-cache"
DOCKER_IMAGE="pistomp-rt-kernel-builder"
CONTAINER_NAME="pistomp-rt-kernel-build-$$"

mkdir -p "${SOURCE_CACHE_DIR}"

# --- Check existing cache ---
if ls "${CACHE_DIR}"/linux-image-${KERNEL_RELEASE}_*.deb &>/dev/null; then
    echo "==> RT kernel packages already cached in ${CACHE_DIR}:"
    ls -lh "${CACHE_DIR}"/linux-*${KERNEL_RELEASE}*.deb "${CACHE_DIR}"/linux-libc-dev*.deb 2>/dev/null || true
    echo ""
    read -rp "Rebuild? [y/N] " -n 1
    echo
    if [[ ! ${REPLY:-n} =~ ^[Yy]$ ]]; then
        echo "==> Keeping existing cached packages."
        exit 0
    fi
    echo "==> Removing old cached packages..."
    rm -f "${CACHE_DIR}"/linux-*${KERNEL_RELEASE}*.deb "${CACHE_DIR}"/linux-libc-dev*.deb
fi

# --- Build Docker image ---
echo "==> Building cross-compilation Docker image..."
docker build -t "${DOCKER_IMAGE}" "${SCRIPT_DIR}/rt-kernel"

# --- Run kernel build ---
echo ""
echo "==> Building RT kernel ${KERNEL_RELEASE} (20–40 minutes)..."
echo ""

docker run --name "${CONTAINER_NAME}" \
    --volume "${SCRIPT_DIR}/rt-kernel:/rt-kernel:ro" \
    --volume "${CACHE_DIR}:/output" \
    --volume "${SOURCE_CACHE_DIR}:/kernel-cache" \
    "${DOCKER_IMAGE}" \
    bash -euo pipefail -c "
        cd /tmp

        TARBALL=\"/kernel-cache/linux-${LINUX_RPI_COMMIT}.tar.gz\"
        echo '==> Fetching RPi Linux at pinned commit ${LINUX_RPI_COMMIT}...'
        if [ ! -f \"\${TARBALL}\" ]; then
            curl -fL "https://github.com/raspberrypi/linux/archive/${LINUX_RPI_COMMIT}.tar.gz" \
                -o \"\${TARBALL}\"
        else
            echo '    (using cached tarball)'
        fi
        mkdir linux-rpi
        tar xz --strip-components=1 -C linux-rpi < \"\${TARBALL}\"
        cd linux-rpi

        echo '==> Configuring kernel (bcm2711_defconfig + RT options)...'
        make ARCH=arm64 bcm2711_defconfig
        cat /rt-kernel/diffconfig >> .config
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- olddefconfig

        echo '==> Verifying PREEMPT_RT is enabled...'
        if ! grep -q 'CONFIG_PREEMPT_RT=y' .config; then
            echo 'ERROR: CONFIG_PREEMPT_RT not enabled after olddefconfig!'
            grep 'CONFIG_PREEMPT' .config || echo '  (no PREEMPT entries found)'
            exit 1
        fi
        echo '    CONFIG_PREEMPT_RT=y confirmed.'

        echo '==> Building .deb packages (this takes a while)...'
        make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
              LOCALVERSION=${KERNEL_LOCALVERSION} \
             -j\$(nproc) bindeb-pkg

        echo '==> Copying packages to output...'
        cp /tmp/linux-image-*.deb /tmp/linux-headers-*.deb /tmp/linux-libc-dev*.deb /output/ 2>/dev/null || true
        echo '==> Done.'
        ls -lh /output/linux-*.deb
    "

BUILD_EXIT=$?

if [ ${BUILD_EXIT} -eq 0 ]; then
    echo ""
    echo "==> RT kernel packages built and cached:"
    ls -lh "${CACHE_DIR}"/linux-*.deb
    echo ""
    echo "Run ./build-docker.sh to build the full image."
    docker rm "${CONTAINER_NAME}"
else
    echo ""
    echo "==> Build FAILED. Container '${CONTAINER_NAME}' preserved for inspection."
    echo "    docker exec -it ${CONTAINER_NAME} bash"
    echo "    docker rm ${CONTAINER_NAME}   # to clean up"
    exit ${BUILD_EXIT}
fi
