ARG BASE_IMAGE=debian:trixie
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive

RUN dpkg --add-architecture arm64 && \
    apt-get -y update && \
    apt-get -y install --no-install-recommends \
        git vim parted \
        quilt coreutils qemu-user-static debootstrap zerofree zip dosfstools \
        libarchive-tools libcap2-bin rsync grep udev xz-utils curl xxd file kmod bc \
        binfmt-support ca-certificates fdisk gpg pigz arch-test \
        dpkg-dev devscripts debhelper-compat \
        python3 python3-dev python3-pip python3-venv python-is-python3 \
        build-essential crossbuild-essential-arm64 \
        cmake meson ninja-build swig \
        libasound2-dev:arm64 libdb5.3-dev:arm64 libdbus-1-dev:arm64 \
        libexpat1-dev:arm64 libfftw3-dev:arm64 libfreetype-dev:arm64 \
        libglib2.0-dev:arm64 \
        libjack-jackd2-dev:arm64 libjpeg-dev:arm64 \
        liblilv-dev:arm64 liblo-dev:arm64 \
        libmp3lame-dev:arm64 libopus-dev:arm64 \
        libpng-dev:arm64 libportmidi-dev:arm64 libpulse-dev:arm64 \
        libreadline-dev:arm64 libsamplerate0-dev:arm64 \
        libsdl2-dev:arm64 libsndfile1-dev:arm64 libsystemd-dev:arm64 \
        libsystemd-dev \
        libv4l-dev:arm64 lv2-dev:arm64 portaudio19-dev:arm64 \
    && rm -rf /var/lib/apt/lists/*

COPY . /pi-gen/

VOLUME [ "/pi-gen/work", "/pi-gen/deploy"]
