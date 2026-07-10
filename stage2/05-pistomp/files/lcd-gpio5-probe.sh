#!/bin/bash
# Diagnostic: does GPIO5 (LCD RESET) have an external pull-up?
#
# lcd-splash leaves the panel initialised and never touches GPIO5, so the
# SoC's power-on pull-up is what holds RESET de-asserted. Blinka's
# DigitalInOut(board.D5) sets the pad to input with PULL=NONE, which removes
# that pull-up. On a board with an external pull-up on RESET the line stays
# high; without one it floats and the panel latches into reset (white screen).
#
# This reproduces exactly that pad state, samples the line, and puts it back.
# Remove this script and lcd-gpio5-probe.service once the question is settled.
set -u

PINCTRL=/usr/bin/pinctrl
GPIO=5
LCD=/usr/bin/lcd-splash
SPLASH=/usr/share/pistomp/splash.rgb565
STAMP=/run/lcd.init

lcd() { "${LCD}" "${SPLASH}" "$1" 2>/dev/null || true; }
sample() { "${PINCTRL}" get "${GPIO}" 2>&1 || true; }

echo "model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null)"
echo "stamp: $([[ -e ${STAMP} ]] && echo present || echo absent)"

echo "--- baseline (splash up, nothing has touched GPIO${GPIO}) ---"
echo "  $(sample)"

lcd "GPIO5 probe: watch"
sleep 3

echo "--- pull disabled (what Blinka's DigitalInOut does) ---"
"${PINCTRL}" set "${GPIO}" ip pn
for i in $(seq 1 15); do
    echo "  t+${i}s $(sample)"
    sleep 1
done

echo "--- pull restored to pull-up ---"
"${PINCTRL}" set "${GPIO}" ip pu
sleep 1
echo "  $(sample)"

# If the panel latched into reset, releasing RESET leaves it awake-but-blank:
# out of reset the ILI9341 powers up sleeping with the display off. A stamped
# lcd-splash call re-sends the registers but skips SLPOUT/DISPON, so it will
# NOT recover the panel. Dropping the stamp forces the full wake.
echo "--- reinit A: stamped lcd-splash (no SLPOUT/DISPON) ---"
lcd "reinit A"
sleep 3

echo "--- reinit B: unstamped lcd-splash (full wake) ---"
rm -f "${STAMP}"
lcd "reinit B"
sleep 3

echo "--- done; GPIO${GPIO} left as: $(sample) ---"
