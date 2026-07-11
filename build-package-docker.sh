#!/usr/bin/env bash
# Build a single debpkgs/<pkg> inside the pi-gen Docker container.
# The built .deb is placed in cache/debpkgs/; the next image build will prefer
# it over the published GitHub Pages version via a high-priority apt override.
# Remove the .deb from cache/debpkgs/ to revert to the released package.
#
# Usage: ./build-package-docker.sh <pkg>
#   e.g. ./build-package-docker.sh jack2-pistomp
set -euo pipefail

if [ $# -lt 1 ]; then
    echo "Usage: $0 <pkg>"
    echo "  e.g. $0 jack2-pistomp"
    exit 1
fi

PKG="$1"
DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

if [ ! -d "${DIR}/debpkgs/${PKG}" ]; then
    echo "Error: debpkgs/${PKG} not found."
    exit 1
fi

if [ ! -f "${DIR}/debpkgs/${PKG}/build.sh" ]; then
    echo "Error: debpkgs/${PKG}/build.sh not found."
    exit 1
fi

DOCKER=${DOCKER:-docker}

# Ensure the pi-gen image exists
if ! ${DOCKER} image inspect pi-gen &>/dev/null; then
    echo "Building pi-gen Docker image..."
    ${DOCKER} build -t pi-gen "${DIR}"
fi

mkdir -p "${DIR}/cache/debpkgs"

# Mount cache/ at /pistomp-cache (same as build-docker.sh).
# Repo is mounted rw because lcd-splash and libfluidsynth2-compat write into
# debpkgs/<pkg>/debian/ as their dpkg-deb staging tree.
echo "==> Building ${PKG} in Docker container..."
TTY_FLAG=""
if [ -t 0 ]; then
    TTY_FLAG="-it"
fi
${DOCKER} run --rm ${TTY_FLAG} \
    --volume "${DIR}/cache":/pistomp-cache:rw \
    --volume "${DIR}":/pistomp:rw \
    -e "CACHE_DIR=/pistomp-cache/debpkgs" \
    -e "WORKDIR=/tmp/build-pkg" \
    -e "UV_CACHE_DIR=/pistomp-cache/uv-cache" \
    -e "UV_PYTHON_INSTALL_DIR=/pistomp-cache/uv-python" \
    -e "PIP_CACHE_DIR=/pistomp-cache/pip-cache" \
    pi-gen \
    bash -c '
        set -e
        mkdir -p /tmp/build-pkg

        # dpkg -s exits 0 for a package that is merely *known* to dpkg
        # ("install ok not-installed"), so match the status field instead.
        is_installed() {
            [ "$(dpkg-query -W -f="\${db:Status-Status}" "$1" 2>/dev/null)" = "installed" ]
        }

        # The Build-Depends field of the package we are building, flattened to one
        # line. Cached debs outside this set are installed opportunistically; only
        # a failure inside it is fatal.
        control=/pistomp/debpkgs/'"${PKG}"'/debian/control
        build_deps=$(awk "/^Build-Depends:/{f=1} f{print} f&&!/^(Build-Depends:| )/{exit}" "$control" | tr "\n," "  ")
        is_build_dep() {
            case " $build_deps " in *" $1 "*|*" $1("*) return 0 ;; *) return 1 ;; esac
        }

        # Install cached debs for build dependencies (mirrors CI build-deb.yml).
        # dpkg -i may fail on install ordering; || true + apt-get -f resolves that.
        # A build dep still not installed afterwards is a real failure (e.g. an
        # unresolvable conflict) — re-run dpkg -i with stderr visible and abort,
        # rather than letting build.sh die later with a confusing unmet build-dep.
        # Others (e.g. pi-stomp, whose runtime deps are not in this container) are
        # expected to fail here and are not needed to build anything.
        for deb in /pistomp-cache/debpkgs/*_arm64.deb; do
            [ -f "$deb" ] || continue
            dep=$(basename "$deb" | sed "s/_.*//")
            [ "$dep" = "'"${PKG}"'" ] && continue
            is_installed "$dep" && continue
            echo "Installing: $dep"
            dpkg -i "$deb" 2>/dev/null || true
            apt-get install -f -y -qq 2>/dev/null || true
            if ! is_installed "$dep"; then
                if is_build_dep "$dep"; then
                    echo "ERROR: build dependency $dep failed to install from $deb" >&2
                    dpkg -i "$deb" || true
                    exit 1
                fi
                echo "Skipped: $dep (not a build dependency of '"${PKG}"')"
            fi
        done
        exec bash /pistomp/debpkgs/'"${PKG}"'/build.sh
    '

echo "==> Done. Package is in cache/debpkgs/."
echo "    The next image build will prefer it over the published version."
echo "    Remove it from cache/debpkgs/ to revert to the released package."
