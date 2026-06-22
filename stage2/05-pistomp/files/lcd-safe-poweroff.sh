#!/bin/bash
case "$1" in
    poweroff|halt)
        /usr/bin/lcd-splash /usr/share/pistomp/splash.rgb565 "Safe to power off"
        ;;
esac
