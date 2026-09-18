#!/bin/bash
# Dump every piece of state that could plausibly differ between two SD cards
# on the same Pi 5 and change whether the RP1 I2S audio path works.
#
# Runs as any user with passwordless sudo. Emits a self-contained tarball.
#
# Usage:  scripts/dump-audio-state.sh [output_dir]
# Default output: /tmp/audio-dump-<hostname>-<UTC-timestamp>

set -u

OUT="${1:-/tmp/audio-dump-$(hostname)-$(date -u +%Y%m%d-%H%M%SZ)}"
mkdir -p "$OUT"
cd "$OUT"

# --- helpers --------------------------------------------------------------

# Run cmd, capture combined stdout+stderr to file. Never abort on failure.
cap()  { local d="$1"; shift; mkdir -p "$(dirname "$d")"; "$@" >"$d" 2>&1 || true; }
scap() { local d="$1"; shift; mkdir -p "$(dirname "$d")"; sudo -n "$@" >"$d" 2>&1 || true; }

# Copy a file/dir preserving perms; keep going if it doesn't exist.
copy() {
    local src="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$src" ]; then
        cp -a "$src" "$dst" 2>/dev/null || sudo -n cp -a "$src" "$dst" 2>/dev/null || true
    else
        printf '%s\n' "[absent]" >"$dst.absent"
    fi
}

# Sha256 every regular file under a directory (sorted for diff-stability).
hashdir() {
    local d="$1"
    if [ -d "$d" ]; then
        (cd "$d" && sudo -n find . -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sudo -n sha256sum 2>/dev/null) || true
    else
        echo "[absent: $d]"
    fi
}

echo "Writing dump to $OUT"

# --- meta -----------------------------------------------------------------

{
    echo "hostname:  $(hostname)"
    echo "date-utc:  $(date -u --iso-8601=seconds)"
    echo "user:      $(id)"
    echo "uname:     $(uname -a)"
    echo "uptime:    $(uptime)"
    echo "script:    $0 $*"
} >meta.txt

cap hardware/cpuinfo.txt         cat /proc/cpuinfo
cap hardware/model.txt           cat /proc/device-tree/model
cap hardware/serial.txt          cat /proc/device-tree/serial-number
cap hardware/loadavg.txt         cat /proc/loadavg
cap hardware/meminfo.txt         cat /proc/meminfo

# --- firmware / bootloader ------------------------------------------------

cap firmware/vcgencmd-version.txt          vcgencmd version
cap firmware/vcgencmd-bootloader.txt       vcgencmd bootloader_version
scap firmware/vcgencmd-bootloader-cfg.txt  vcgencmd bootloader_config
cap firmware/vcgencmd-get-config-int.txt   vcgencmd get_config int
cap firmware/vcgencmd-get-config-str.txt   vcgencmd get_config str
cap firmware/measure-clocks.txt bash -c '
    for c in arm core h264 isp v3d uart pwm emmc pixel vec hdmi dpi \
             dram_arm dram_core dram_p dram_i dram_c gpu; do
        printf "%-12s " "$c"; vcgencmd measure_clock "$c" 2>&1
    done'
scap firmware/eeprom-update.txt   rpi-eeprom-update
scap firmware/eeprom-config.txt   rpi-eeprom-config

# --- /boot/firmware content ------------------------------------------------

scap boot/listing.txt             ls -laR /boot/firmware
scap boot/hashes.sha256 bash -c '
    cd /boot/firmware && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum'
copy /boot/firmware/config.txt        boot/config.txt
copy /boot/firmware/cmdline.txt       boot/cmdline.txt
copy /boot/firmware/pistomp.conf      boot/pistomp.conf
copy /boot/pistomp.conf               boot/pistomp.conf.rootpart
copy /proc/cmdline                    boot/proc-cmdline.txt

# --- device tree (as running) ---------------------------------------------

# Live DT hashes: does any node payload differ between cards? Everything the
# firmware and overlays configured lives here.
scap dt/hashes.sha256 bash -c '
    cd /proc/device-tree && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum'
scap dt/tree.tar bash -c 'cd /proc && tar -cf - device-tree'
if command -v dtc >/dev/null 2>&1; then
    scap dt/tree.dts dtc -q -I fs -O dts /proc/device-tree
fi
scap dt/overlays.txt dtoverlay -l

# --- kernel modules --------------------------------------------------------

cap  modules/lsmod.txt              lsmod
cap  modules/proc-modules.txt       cat /proc/modules
KREL="$(uname -r)"
cap  modules/kernel-release.txt     bash -c "echo $KREL"
# Hash every module — order-independent diff of what's installed.
scap modules/ko-hashes.sha256 bash -c "
    d=/lib/modules/$KREL
    find \"\$d\" -type f \\( -name '*.ko' -o -name '*.ko.xz' -o -name '*.ko.zst' -o -name '*.ko.gz' \\) \
        -printf '%P\n' | LC_ALL=C sort | while read -r f; do
        sha256sum \"\$d/\$f\" | awk -v p=\"\$f\" '{print \$1\"  \"p}'
    done"
# Metadata files that must match between kernels of the same release.
scap modules/metadata.sha256 bash -c "
    cd /lib/modules/$KREL && sha256sum modules.dep modules.alias modules.symbols \
        modules.builtin modules.builtin.modinfo 2>/dev/null | LC_ALL=C sort"
# modinfo for every module that participates in the audio path.
{
    for m in da7213 snd_soc_rpi_codeczero snd_soc_iqaudio_codec snd_soc_hifiberry_dacplusadc \
             snd_soc_audioinjector_wm8731 snd_soc_bcm2835_i2s dw_axi_dmac_platform \
             snd_soc_core snd_pcm_dmaengine snd_soc_simple_card snd_soc_simple_card_utils \
             snd_hda_intel snd_usb_audio rp1_pio pinctrl_rp1; do
        echo "=== $m ==="; modinfo "$m" 2>&1; echo
    done
} >modules/audio-modinfo.txt

# --- modprobe / modules-load / blacklist ----------------------------------

scap modprobe/etc-hashes.sha256   bash -c 'find /etc/modprobe.d  -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum'
scap modprobe/lib-hashes.sha256   bash -c 'find /lib/modprobe.d  -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum'
scap modprobe/etc.tar             bash -c 'tar -cf - -C / etc/modprobe.d 2>/dev/null'
scap modprobe/lib.tar             bash -c 'tar -cf - -C / lib/modprobe.d 2>/dev/null'
copy /etc/modules                 modules-load/etc-modules.txt
scap modules-load/dir.tar         bash -c 'tar -cf - -C / etc/modules-load.d 2>/dev/null'

# --- udev rules ------------------------------------------------------------

scap udev/etc-hashes.sha256       bash -c 'find /etc/udev/rules.d -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum'
scap udev/lib-hashes.sha256       bash -c 'find /lib/udev/rules.d -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 sha256sum'
scap udev/etc-rules.tar           bash -c 'tar -cf - -C / etc/udev/rules.d 2>/dev/null'
scap udev/lib-rules.tar           bash -c 'tar -cf - -C / lib/udev/rules.d 2>/dev/null'

# --- ALSA / ASoC -----------------------------------------------------------

cap  alsa/cards.txt         cat /proc/asound/cards
cap  alsa/pcm.txt           cat /proc/asound/pcm
cap  alsa/modules.txt       cat /proc/asound/modules
cap  alsa/version.txt       cat /proc/asound/version
cap  alsa/devices.txt       cat /proc/asound/devices
cap  alsa/aplay-l.txt       aplay -l
cap  alsa/arecord-l.txt     arecord -l
cap  alsa/aplay-L.txt       aplay -L
copy /var/lib/alsa/asound.state       alsa/asound.state
copy /etc/asound.conf                 alsa/asound.conf
copy /etc/alsa                        alsa/etc-alsa
scap asoc/tree.txt bash -c '
    if [ -d /sys/kernel/debug/asoc ]; then
        find /sys/kernel/debug/asoc -maxdepth 6 | sort
        echo
        find /sys/kernel/debug/asoc -type f 2>/dev/null | sort | while read -r f; do
            echo "=== $f ==="; cat "$f" 2>/dev/null || echo "[unreadable]"; echo
        done
    fi'

# --- pinctrl / clocks / DMA -----------------------------------------------

scap pinctrl/gpio.txt bash -c '
    for p in $(seq 0 53); do pinctrl get "$p"; done'
scap pinctrl/pinmux-pins.txt bash -c '
    for f in /sys/kernel/debug/pinctrl/*/pinmux-pins; do
        echo "=== $f ==="; cat "$f" 2>/dev/null; echo
    done'
scap pinctrl/pins-status.txt bash -c '
    for f in /sys/kernel/debug/pinctrl/*/pins; do
        echo "=== $f ==="; cat "$f" 2>/dev/null; echo
    done'
scap clocks/clk_summary.txt cat /sys/kernel/debug/clk/clk_summary
scap clocks/clk_orphan_summary.txt cat /sys/kernel/debug/clk/clk_orphan_summary
scap dma/channels.txt bash -c '
    for c in /sys/class/dma/*chan*; do
        [ -e "$c" ] || continue
        printf "%-30s slave=%s in_use=%s\n" \
            "$(basename "$c")" \
            "$(readlink "$c/slave" 2>/dev/null)" \
            "$(cat "$c/in_use" 2>/dev/null)"
    done'
scap dma/engine-summary.txt cat /sys/kernel/debug/dmaengine/summary
scap dma/dmac-registers.txt bash -c '
    for f in /sys/kernel/debug/dw_axi_dmac*/*; do
        [ -f "$f" ] || continue
        echo "=== $f ==="; cat "$f" 2>/dev/null; echo
    done'

# --- IRQ / real-time ------------------------------------------------------

cap  irq/interrupts.txt     cat /proc/interrupts
cap  irq/rt-threads.txt bash -c 'ps -eLo pid,tid,cls,rtprio,pri,ni,psr,comm | awk "NR==1 || /irq|jack|dma|audio/"'
cap  irq/proc-softirqs.txt  cat /proc/softirqs
scap irq/proc-irq-tree.txt  bash -c 'find /proc/irq -maxdepth 2 -name smp_affinity_list -print -exec cat {} \; | paste - -'

# --- systemd ---------------------------------------------------------------

cap  systemd/units-all.txt        systemctl list-units --all --no-pager --plain
cap  systemd/unit-files.txt       systemctl list-unit-files --no-pager --plain
cap  systemd/failed.txt           systemctl list-units --failed --no-pager --plain
cap  systemd/audio-show.txt bash -c '
    for u in mod-host jack pistomp-recovery pistomp-audio-irq mod-ui firstboot \
             regenerate-ssh-host-keys wait-for-jack rtirq lcd-splash; do
        echo "=== $u ==="; systemctl show "$u" --no-pager 2>&1
        echo "--- unit file ---"; systemctl cat "$u" --no-pager 2>&1
        echo
    done'
scap systemd/etc-tree.txt bash -c 'find /etc/systemd -type f -o -type l | sort | xargs ls -la'
scap systemd/etc-hashes.sha256 bash -c 'find /etc/systemd -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum'
scap systemd/etc.tar bash -c 'tar -cf - -C / etc/systemd'

# --- packages --------------------------------------------------------------

cap  packages/dpkg-list.txt         dpkg-query -W -f='${Package} ${Version} ${Status} ${Architecture}\n'
cap  packages/dpkg-selections.txt   dpkg --get-selections
cap  packages/apt-mark-manual.txt   apt-mark showmanual
cap  packages/apt-mark-hold.txt     apt-mark showhold
cap  packages/apt-mark-auto.txt     apt-mark showauto
scap packages/apt-sources.tar       bash -c 'tar -cf - -C / etc/apt/sources.list etc/apt/sources.list.d etc/apt/preferences.d 2>/dev/null'
scap packages/apt-sources-hashes.sha256 bash -c '
    { [ -f /etc/apt/sources.list ] && sha256sum /etc/apt/sources.list
      find /etc/apt/sources.list.d /etc/apt/preferences.d -type f 2>/dev/null | sort | xargs sha256sum 2>/dev/null; } | LC_ALL=C sort'
scap packages/dpkg-conffiles-md5.txt bash -c '
    # Any user-edited dpkg conffile? md5sum vs shipped md5 catches it.
    find /var/lib/dpkg/info -name "*.md5sums" -print | sort | while read -r f; do
        pkg=$(basename "$f" .md5sums)
        while read -r md file; do
            path="/$file"
            [ -f "$path" ] || continue
            actual=$(md5sum "$path" 2>/dev/null | awk "{print \$1}")
            [ "$actual" = "$md" ] || echo "$pkg $file  expected=$md  actual=$actual"
        done <"$f"
    done'

# --- OS identity ----------------------------------------------------------

copy /etc/os-release           os/os-release.txt
copy /etc/rpi-issue            os/rpi-issue.txt
copy /etc/debian_version       os/debian_version.txt
copy /etc/issue                os/issue.txt

# --- JACK / pi-Stomp configs ----------------------------------------------

copy /etc/default/jack                    jack/default.txt
copy /usr/lib/pistomp/jackdrc             jack/jackdrc
copy /etc/jackdrc                         jack/etc-jackdrc
copy /etc/jackdrc.obsolete                jack/etc-jackdrc.obsolete
copy /usr/lib/pistomp/wait-for-jack.sh    jack/wait-for-jack.sh
copy /usr/local/bin/wait-for-jack.sh      jack/wait-for-jack-usrlocal.sh

# --- realtime / IRQ tuning -------------------------------------------------

scap rt/limits-hashes.sha256   bash -c 'find /etc/security -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum'
scap rt/limits.tar             bash -c 'tar -cf - -C / etc/security'
copy /etc/default/rtirq                   rt/default-rtirq.txt
copy /usr/lib/pistomp/rtirq.conf          rt/pistomp-rtirq.conf
copy /usr/lib/pistomp/pistomp-audio-irq.py  rt/pistomp-audio-irq.py

# --- mounts / cpu ---------------------------------------------------------

cap  mounts/proc.txt          cat /proc/mounts
cap  mounts/self-mountinfo.txt cat /proc/self/mountinfo
copy /etc/fstab               mounts/fstab.txt
cap  cpu/cpufreq.txt bash -c '
    for c in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
        echo "=== $c ==="
        for f in scaling_governor scaling_cur_freq scaling_min_freq scaling_max_freq cpuinfo_cur_freq; do
            printf "  %-22s %s\n" "$f" "$(cat "$c/$f" 2>/dev/null)"
        done
    done'
cap cpu/online.txt            cat /sys/devices/system/cpu/online
cap cpu/isolated.txt          cat /sys/devices/system/cpu/isolated

# --- firmware blobs (RP1 + Broadcom bootloader) ---------------------------

scap fw/lib-firmware-hashes.sha256 bash -c '
    for d in /lib/firmware/raspberrypi /lib/firmware/brcm /lib/firmware/rpi \
             /lib/firmware/updates/raspberrypi /lib/firmware/updates/brcm; do
        [ -d "$d" ] && find "$d" -type f -print0 2>/dev/null
    done | LC_ALL=C sort -z | xargs -0 -r sha256sum 2>/dev/null'

# --- journals -------------------------------------------------------------

scap journals/boots.txt              journalctl --list-boots --no-pager
scap journals/dmesg.txt              dmesg -T
scap journals/kernel-b0.txt          journalctl -k -b 0 --no-pager
scap journals/kernel-b0-abs.txt      journalctl -k -b 0 --no-pager -o short-monotonic
for u in jack mod-host mod-ui pistomp-recovery pistomp-audio-irq firstboot \
         wait-for-jack rtirq lcd-splash regenerate-ssh-host-keys; do
    scap "journals/$u-b0.txt" journalctl -u "$u" -b 0 --no-pager
done

# --- tarball & done -------------------------------------------------------

cd "$(dirname "$OUT")"
base="$(basename "$OUT")"
tar -czf "$base.tar.gz" "$base"
size=$(du -sh "$base.tar.gz" | awk '{print $1}')
echo
echo "Dump complete."
echo "  Directory: $OUT"
echo "  Tarball:   $OUT.tar.gz  ($size)"
echo
echo "Fetch with:  scp <user>@<host>:$OUT.tar.gz ."
