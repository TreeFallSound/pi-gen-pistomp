#!/bin/sh
TOUCHOSC2MIDI=/opt/pistomp/venvs/touchosc2midi/bin/touchosc2midi
IN_PORT_ID=$($TOUCHOSC2MIDI list ports 2>&1 | grep touchosc | head -n 1 | egrep -o "\s+[0-9]+: " | egrep -o "[0-9]+")
OUT_PORT_ID=$($TOUCHOSC2MIDI list ports 2>&1 | grep touchosc | tail -n 1 | egrep -o "\s+[0-9]+: " | egrep -o "[0-9]+")
exec $TOUCHOSC2MIDI --midi-in=$IN_PORT_ID --midi-out=$OUT_PORT_ID
