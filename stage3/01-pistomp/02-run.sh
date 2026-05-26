#!/bin/bash -e

on_chroot << EOF
UV_PROJECT_ENVIRONMENT=/opt/pistomp/venvs/pi-stomp \
    /usr/local/bin/uv sync --frozen --no-dev --extra hardware \
    --project /home/${FIRST_USER_NAME}/pi-stomp
EOF
