#!/bin/bash
case "$1" in
    poweroff|halt)
        /usr/bin/lcd-splash /usr/share/pistomp/splash/splash-poweroff.rgb565 "Safe to power off"
        ;;
esac
