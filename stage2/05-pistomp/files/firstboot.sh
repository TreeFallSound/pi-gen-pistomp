#!/bin/sh

sudo chown -R pistomp:pistomp /home/pistomp/

logger --priority info --tag firstboot.sh "Changing config.txt to use real time kernel"
sudo cp /boot/firmware/config.txt /boot/firmware/config_orig.txt
sudo cp /boot/firmware/config_pistomp.txt /boot/firmware/config.txt

logger --priority info --tag firstboot.sh "Copy audiocard settings"
#/home/pistomp/pi-stomp/util/change-audio-card.sh iqaudio-codec
sudo cp /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state /var/lib/alsa/asound.state

logger --priority info --tag firstboot.sh "Modify pistomp version"
# Lame assumption that pi3 implies pistomp v2
if $(cat /proc/cpuinfo | grep Model | grep -q 'Pi 3'); then
  runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 2.0
else
  runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 3.0
fi

logger --priority info --tag firstboot.sh "Disable unnecessary services"
sudo systemctl disable --now dnsmasq.service
sudo systemctl disable --now hciuart.service
sudo systemctl disable --now bluetooth.service

logger --priority info --tag firstboot.sh "Rename this file and reboot"
sudo mv "$0" /boot/firmware/firstboot.done
sudo reboot
