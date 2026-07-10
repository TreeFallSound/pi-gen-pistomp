#!/bin/bash -e

install -m 755 files/firstboot.sh  ${ROOTFS_DIR}/boot/firmware/
install -m 644 files/pistomp.conf  ${ROOTFS_DIR}/boot/firmware/

on_chroot << EOF

chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}
rm -f /etc/profile.d/bash_completion.sh

EOF
