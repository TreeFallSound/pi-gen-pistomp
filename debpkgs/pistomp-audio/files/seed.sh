#!/bin/bash
# Seed /var/lib/alsa/asound.state from the packaged known-good card state.
#
# Usage: seed.sh <overlay>
#   overlay: a device-tree overlay name from the mapping below
#            (iqaudio-codec | hifiberry-dacplusadc | audioinjector-wm8731-audio)
#
# Copies the matching state file over the global one. The whole file is
# written: sections for other cards are clobbered. Then applies it live if
# the card is fitted; -I keeps alsactl from resetting a card that isn't.

set -euo pipefail

STATE_DIR="/usr/lib/pistomp/alsa"
STATE_FILE="/var/lib/alsa/asound.state"

usage() {
    echo "Usage: $0 <overlay>" >&2
    echo "  overlay: iqaudio-codec | hifiberry-dacplusadc | audioinjector-wm8731-audio" >&2
    exit 2
}

[ $# -eq 1 ] || usage

case "$1" in
    iqaudio-codec)              STATE="iqaudiocodec.state" ;;
    hifiberry-dacplusadc)       STATE="hifiberry.state" ;;
    audioinjector-wm8731-audio) STATE="audioinjector.state" ;;
    *)
        echo "seed.sh: unknown overlay '$1'" >&2
        exit 1
        ;;
esac

if [ ! -r "${STATE_DIR}/${STATE}" ]; then
    echo "seed.sh: missing state file ${STATE_DIR}/${STATE}" >&2
    exit 1
fi

install -m 644 "${STATE_DIR}/${STATE}" "${STATE_FILE}"
echo "seed.sh: seeded ${STATE_FILE} from ${STATE_DIR}/${STATE}"

/usr/sbin/alsactl --no-ucm -I -f "${STATE_FILE}" restore
