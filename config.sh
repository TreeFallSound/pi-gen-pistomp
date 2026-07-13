#!/bin/bash
# pistomp-gen build configuration — source this, do not execute.
# All upstream URLs, branches, and version pins live here.
#
# set -a auto-exports every variable so dpkg-buildpackage's make subprocess
# can read them directly in debian/rules without explicit export statements.
set -a

# --- RT Kernel ---
KERNEL_VERSION="6.18.36"
KERNEL_LOCALVERSION="-rpi-v8-rt"  # suffix in uname -r; must contain -rpi- so raspi-firmware's initramfs hook recognises the flavour
LINUX_RPI_COMMIT="954341c412dd48b7c7f8125d81212ec4c0e42ed3"

# --- JACK2 ---
JACK2_REPO="https://github.com/jackaudio/jack2.git"
JACK2_TAG="v1.9.22"

# --- lg (lgpio — GPIO library used by lcd-splash) ---
LG_REPO="https://github.com/joan2937/lg.git"
LG_TAG="v0.2.2"

# --- Hylia ---
HYLIA_REPO="https://github.com/falkTX/Hylia.git"
HYLIA_REF="master"  # no stable tag; pin by commit when needed

# --- mod-host ---
MOD_HOST_REPO="https://github.com/TreeFallSound/mod-host.git"
MOD_HOST_BRANCH="master"

# --- mod-ui ---
MOD_UI_REPO="https://github.com/TreeFallSound/mod-ui.git"
MOD_UI_BRANCH="main"

# --- browsepy ---
BROWSEPY_REPO="https://github.com/micahvdm/browsepy.git"
BROWSEPY_REF="master"

# --- amidithru ---
AMIDITHRU_REPO="https://github.com/BlokasLabs/amidithru.git"
AMIDITHRU_REF="master"

# --- touchosc2midi ---
TOUCHOSC2MIDI_REPO="https://github.com/BlokasLabs/touchosc2midi.git"
TOUCHOSC2MIDI_REF="master"

# --- mod-midi-merger ---
MOD_MIDI_MERGER_REPO="https://github.com/mod-audio/mod-midi-merger.git"
MOD_MIDI_MERGER_REF="master"

# --- mod-ttymidi ---
MOD_TTYMIDI_REPO="https://github.com/moddevices/mod-ttymidi.git"
MOD_TTYMIDI_REF="master"

# --- pi-stomp (application) ---
PISTOMP_REPO="https://github.com/TreeFallSound/pi-stomp.git"
PISTOMP_BRANCH="prerelease-for-v2"

# --- pistomp-recovery ---
PISTOMP_RECOVERY_REPO="https://github.com/TreeFallSound/pistomp-recovery.git"
PISTOMP_RECOVERY_BRANCH="main"

# --- JackBridge (netJACK2 DAW recording over Ethernet) ---
JACKROUTER_REPO="https://github.com/TreeFallSound/JackRouter.git"
JACKROUTER_REF="master"

# --- Pedalboards / user files ---
PEDALBOARDS_REPO="https://github.com/TreeFallSound/pi-stomp-pedalboards.git"
PEDALBOARDS_BRANCH="master"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

# --- ffmpeg-pistomp ---
FFMPEG_VERSION="7.1.1"
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

# --- sfizz ---
SFIZZ_REPO="https://github.com/sfztools/sfizz-ui.git"
SFIZZ_TAG="1.2.3"

# --- fluidsynth-headless ---
FLUIDSYNTH_VERSION="2.5.2"
FLUIDSYNTH_URL="https://github.com/FluidSynth/fluidsynth/archive/v${FLUIDSYNTH_VERSION}.tar.gz"

# --- jack-capture ---
JACK_CAPTURE_REPO="https://github.com/kmatheussen/jack_capture.git"
# Upstream master (commit a539d444, 2023-01-04) contains all post-0.9.73 fixes.
# The tag 0.9.73 (2017) is missing ARM build fixes, C99 compatibility, and more.
JACK_CAPTURE_REF="a539d444d388c4cfed7279e385830e7767d59c41"

# --- VeJa Cabinet Simulator LV2 plugin (pistomp fork) ---
CABSIM_LV2_REPO="https://github.com/VeJa-Plugins/Cabinet-Simulator.git"
CABSIM_LV2_REF="master"

# --- VeJa Bass Cabinets LV2 plugin (pistomp fork) ---
VEJA_BASS_CAB_REPO="https://github.com/VeJa-Plugins/Bass-Cabinets.git"
VEJA_BASS_CAB_REF="master"

# --- VeJa Marshall 1960 Cabinet LV2 plugin (pistomp fork) ---
VEJA_1960_CAB_REPO="https://github.com/VeJa-Plugins/Marshall-1960.git"
VEJA_1960_CAB_REF="master"

# --- LV2 plugins tarball ---
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""

# --- NAM reamp signal (tone3000 redirects to S3; stable canonical URL) ---
NAM_REAMP_URL="https://www.tone3000.com/T3K-sweep-v3.wav"

# --- Python (uv-managed, for mod-ui venv only) ---
MOD_UI_PYTHON_VERSION="3.11"

# --- apt repo (GitHub Pages) ---
# Base URL of the GitHub Pages site serving the OTA apt repo. The device's
# /etc/apt/sources.list.d/pistomp.list is built from this in
# stage2/05-pistomp/05-run.sh. Must match the Pages URL of the repo that
# publishes via .github/workflows/publish-apt-repo.yml.
APT_REPO_URL="https://treefallsound.github.io/pi-gen-pistomp"
APT_REPO_SUITE="trixie"
APT_REPO_TESTING_SUITE="trixie-testing"  # only used when IMG_CHANNEL=testing
APT_REPO_COMPONENT="main"
APT_REPO_ARCH="arm64"
