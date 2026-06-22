#!/bin/bash
# pistomp-gen build configuration — source this, do not execute.
# All upstream URLs, branches, and version pins live here.

# --- RT Kernel ---
KERNEL_VERSION="6.18.36"
KERNEL_LOCALVERSION="-rt-v8+"                          # suffix in uname -r
LINUX_RPI_COMMIT="954341c412dd48b7c7f8125d81212ec4c0e42ed3"

# --- JACK2 ---
JACK2_REPO="https://github.com/jackaudio/jack2.git"
JACK2_TAG="v1.9.22"

# --- Hylia ---
HYLIA_REPO="https://github.com/falkTX/Hylia.git"
HYLIA_REF="master"                                     # no stable tag; pin by commit when needed

# --- mod-host ---
MOD_HOST_REPO="https://github.com/sastraxi/mod-host.git"
MOD_HOST_BRANCH="fix/effect-drain-midi"

# --- mod-ui ---
MODUI_REPO="https://github.com/TreeFallSound/mod-ui.git"
MODUI_BRANCH="master"

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
PISTOMP_BRANCH="pistomp-v3"

# --- Pedalboards / user files ---
PEDALBOARDS_REPO="https://github.com/TreeFallSound/pi-stomp-pedalboards.git"
PEDALBOARDS_BRANCH="master"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

# --- sfizz ---
SFIZZ_REPO="https://github.com/sfztools/sfizz-ui.git"
SFIZZ_TAG="1.2.3"

# --- fluidsynth-headless ---
FLUIDSYNTH_VERSION="2.5.2"
FLUIDSYNTH_URL="https://github.com/FluidSynth/fluidsynth/archive/v${FLUIDSYNTH_VERSION}.tar.gz"

# --- jack-capture ---
JACK_CAPTURE_REPO="https://github.com/kmatheussen/jack_capture.git"
JACK_CAPTURE_TAG="0.9.73"

# --- LV2 plugins tarball ---
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""

# --- Python (uv-managed, for mod-ui venv only) ---
MOD_UI_PYTHON_VERSION="3.11"

# --- apt repo (GitHub Pages) ---
APT_REPO_SUITE="trixie"
APT_REPO_COMPONENT="main"
APT_REPO_ARCH="arm64"
