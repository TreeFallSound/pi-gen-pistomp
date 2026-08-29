#!/bin/bash
# volt-monitor.sh — live scrolling monitor of the Pi 5 EXT5V (5V input) rail.
#
# Usage: ./volt-monitor.sh [interval_seconds]    (default 1)
#
#   Column markers:  ! = 4.63V undervoltage trip      : = 5.10V nominal
#                    (uv/thr suppressed when the matching NOW flag is shown)

set -uo pipefail

INTERVAL="${1:-1}"

VMIN=4.55        # left edge of the plot
VMAX=5.15        # right edge
UV_TRIP=4.63     # firmware under-voltage threshold
NOMINAL=5.10     # what the supply should actually be delivering
WARN=4.80        # amber below this

HWMON=""
for h in /sys/class/hwmon/hwmon*; do
    [ -r "$h/name" ] || continue
    if [ "$(cat "$h/name" 2>/dev/null)" = "rpi_volt" ]; then HWMON="$h"; break; fi
done

if ! command -v vcgencmd >/dev/null 2>&1; then
    echo "volt-monitor: vcgencmd not found (install raspi-utils)" >&2
    exit 1
fi

# EXT5V_V is a Pi 5 PMIC rail. Earlier Pis have no equivalent ADC, so fail
# with an explanation rather than silently plotting nothing.
if ! vcgencmd pmic_read_adc EXT5V_V 2>/dev/null | grep -q EXT5V_V; then
    echo "volt-monitor: no EXT5V_V rail — this needs a Pi 5 (PMIC ADC)." >&2
    echo "              On Pi 3/4 use: watch -n1 vcgencmd get_throttled" >&2
    exit 1
fi

W=0
recalc_width() { W=$(( $(tput cols 2>/dev/null || echo 80) - 34 )); [ "$W" -lt 20 ] && W=20; }
recalc_width
trap recalc_width WINCH

if [ -t 1 ]; then C_RST=$'\033[0m'; C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_DIM=$'\033[2m'
else C_RST=""; C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""; fi

OBS_MIN=99; OBS_MAX=0; SAMPLES=0; UV_HITS=0

summary() {
    [ "$SAMPLES" -eq 0 ] && exit 0
    printf '\n%s' "$C_DIM"
    printf -- '-%.0s' $(seq 1 40); printf '\n'
    printf 'samples %d   min %.3fV   max %.3fV   under-voltage on %d (%d%%)\n%s' \
        "$SAMPLES" "$OBS_MIN" "$OBS_MAX" "$UV_HITS" \
        "$(( SAMPLES ? UV_HITS * 100 / SAMPLES : 0 ))" "$C_RST"
    exit 0
}
trap summary INT TERM

printf '%s%s  %s..%sV   ! = %sV trip   : = %sV nominal   (Ctrl-C for summary)%s\n' \
    "$C_DIM" "$(date '+%F %T')" "$VMIN" "$VMAX" "$UV_TRIP" "$NOMINAL" "$C_RST"

while :; do
    v=$(vcgencmd pmic_read_adc EXT5V_V 2>/dev/null | grep -oE '=[0-9.]+V' | tr -dc '0-9.')
    t=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    a=$([ -n "$HWMON" ] && cat "$HWMON/in0_lcrit_alarm" 2>/dev/null || echo "?")

    if [ -z "$v" ]; then sleep "$INTERVAL"; continue; fi

    read -r OBS_MIN OBS_MAX ROW < <(awk \
        -v v="$v" -v mn="$OBS_MIN" -v mx="$OBS_MAX" \
        -v vmin="$VMIN" -v vmax="$VMAX" -v w="$W" \
        -v trip="$UV_TRIP" -v nom="$NOMINAL" 'BEGIN {
        if (v < mn) mn = v; if (v > mx) mx = v;
        col = function_col(v);
        tcol = function_col(trip);
        ncol = function_col(nom);
        s = "";
        for (i = 0; i < w; i++) {
            if      (i == col)  s = s "#";
            else if (i == tcol) s = s "!";
            else if (i == ncol) s = s ":";
            else if (i < col)   s = s "=";
            else                s = s " ";
        }
        printf "%.5f %.5f %s\n", mn, mx, s;
    }
    function function_col(x,   c) {
        c = int((x - vmin) / (vmax - vmin) * (w - 1) + 0.5);
        if (c < 0) c = 0; if (c > w - 1) c = w - 1;
        return c;
    }')

    # Colour by severity; decode the live throttle bits.
    col=$C_GRN
    awk -v v="$v" -v t="$UV_TRIP" 'BEGIN{exit !(v < t)}' && col=$C_RED || \
      { awk -v v="$v" -v t="$WARN" 'BEGIN{exit !(v < t)}' && col=$C_YEL; }

    flags=""
    tn=$(( t )) 2>/dev/null || tn=0
    (( tn & 0x1 ))     && { flags="${flags}${C_RED} UV${C_RST}"; UV_HITS=$((UV_HITS+1)); }
    (( tn & 0x4 ))     && flags="${flags}${C_RED} THR${C_RST}"
    (( tn & 0x10000 )) && (( !(tn & 0x1) )) && flags="${flags}${C_DIM} uv${C_RST}"
    (( tn & 0x40000 )) && (( !(tn & 0x4) )) && flags="${flags}${C_DIM} thr${C_RST}"
    [ "$a" = "1" ] && flags="${flags}${C_YEL} lcrit${C_RST}"

    SAMPLES=$((SAMPLES+1))
    printf '%s%s%s %s%s%s %s%6.3fV%s%b\n' \
        "$C_DIM" "$(date '+%H:%M:%S')" "$C_RST" \
        "$col" "$ROW" "$C_RST" "$col" "$v" "$C_RST" "$flags"

    sleep "$INTERVAL"
done
