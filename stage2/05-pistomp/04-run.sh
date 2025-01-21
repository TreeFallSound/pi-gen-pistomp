#!/bin/bash

install -m 755 files/firstboot.sh ${ROOTFS_DIR}/boot/firmware/

on_chroot << EOF

chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}
chmod +x /etc/jackdrc
chown jack:jack /etc/jackdrc
chmod 500 /etc/authbind/byport/80
chown ${FIRST_USER_NAME}:${FIRST_USER_NAME} /etc/authbind/byport/80
rm /etc/profile.d/bash_completion.sh

EOF
