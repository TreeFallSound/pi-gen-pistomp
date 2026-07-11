#!/bin/bash -e
# Run on an already-flashed pi-Stomp device to switch its apt source from the
# old sastraxi.github.io-hosted repo to the current treefallsound.github.io one.
#
# Usage:
#   scp scripts/migrate-apt-repo.sh pistomp@pistomp.local:~
#   ssh pistomp@pistomp.local  
#     ~/migrate-apt-repo.sh
#     rm ~/migrate-apt-repo.sh  

OLD_URL="https://sastraxi.github.io/pi-gen-pistomp"
NEW_URL="https://treefallsound.github.io/pi-gen-pistomp"
SUITE="trixie"
COMPONENT="main"
ARCH="arm64"
LIST="/etc/apt/sources.list.d/pistomp.list"

if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

if [ -f "$LIST" ] && grep -q "$OLD_URL" "$LIST"; then
    echo "Found old repo in $LIST, replacing..."
else
    echo "No reference to $OLD_URL found in $LIST — nothing to migrate."
fi

echo "deb [arch=${ARCH} trusted=yes] ${NEW_URL} ${SUITE} ${COMPONENT}" > "$LIST"
echo "Wrote $LIST:"
cat "$LIST"

# Remove any stale local-override source left from a pre-OTA image.
if [ -f /etc/apt/sources.list.d/pistomp-local.list ]; then
    echo "Removing stale /etc/apt/sources.list.d/pistomp-local.list"
    rm -f /etc/apt/sources.list.d/pistomp-local.list
fi

apt-get update -qq
echo "Done. Repo now points at ${NEW_URL}."
