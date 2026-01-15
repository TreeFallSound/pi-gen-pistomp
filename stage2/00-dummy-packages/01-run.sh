#!/bin/bash

apt update && apt-get -y install equivs
export DEB_BUILD_OPTIONS="nocheck"
export DPKG_DEB_COMPRESSOR=gzip
equivs-build files/jack-dummy.ctl
cp jack-dummy_1.9.22_all.deb ${ROOTFS_DIR}/

on_chroot << EOF
dpkg -i /jack-dummy_1.9.22_all.deb
rm /jack-dummy_1.9.22_all.deb
EOF
