#!/bin/bash
# pi-Stomp read-only rootfs recovery
#
# If the root filesystem was remounted read-only by the kernel due to an ext4
# error, normal service startup is going to fail (JACK cannot write its config,
# mod-ui cannot write pedalboards, etc.). This script detects a read-only root
# mount and reboots, giving systemd-fsck another chance to repair the
# filesystem on the next boot.
#
# A persistent retry counter in /boot prevents infinite reboot loops if the
# filesystem is genuinely unrecoverable. We allow at most 2 consecutive
# read-only boots before giving up. /boot is FAT32 and is mounted before
# this service runs, so the counter is available even when the rootfs is RO.
#
# Disable entirely by passing `pistomp.ro.recovery=0` on the kernel cmdline.
# Test overrides: PISTOMP_RO_RECOVERY_ROOT, PISTOMP_RO_RECOVERY_BOOT,
# PISTOMP_RO_RECOVERY_NO_REBOOT.

# Allow overriding root/boot paths for testing in a mount namespace.
ROOT="${PISTOMP_RO_RECOVERY_ROOT:-/}"
# /boot is FAT32 and mounted early; safe place to keep a cross-boot counter
# even when rootfs is read-only.
COUNTER_FILE="${PISTOMP_RO_RECOVERY_BOOT:-/boot/firmware}/pistomp-ro-recovery-count"
MAX_RETRIES=2
DELAY_SEC=5

log() {
    echo "pistomp-ro-recovery: $*" >&2
    logger -t pistomp-ro-recovery "$*" || true
}

# Check kernel cmdline for disable switch.
if [[ -r /proc/cmdline ]] && grep -q 'pistomp\.ro\.recovery=0' /proc/cmdline; then
    log "disabled by kernel cmdline (pistomp.ro.recovery=0)"
    exit 0
fi

# Determine whether root is currently writable. We deliberately try to create
# a temporary file rather than parsing mount options, because the kernel may
# have silently remounted read-only after boot even though /proc/mounts still
# says "rw".
root_writable=no
if touch "${ROOT}/.pistomp-ro-recovery-test" 2>/dev/null; then
    rm -f "${ROOT}/.pistomp-ro-recovery-test"
    root_writable=yes
fi

if [[ "${root_writable}" == "yes" ]]; then
    # Root is writable: clear the retry counter and exit cleanly.
    rm -f "${COUNTER_FILE}" 2>/dev/null || true
    log "rootfs is writable, proceeding with normal boot"
    exit 0
fi

# Root is read-only. We need /boot to be writable so we can persist a retry
# counter and avoid an infinite reboot loop. If /boot is not writable, abort.
if ! touch "${COUNTER_FILE}.test" 2>/dev/null; then
    log "rootfs is read-only and /boot is not writable; cannot safely recover, aborting"
    exit 0
fi
rm -f "${COUNTER_FILE}.test"

# Read/update the retry counter from /boot.
retries=0
if [[ -f "${COUNTER_FILE}" ]]; then
    retries="$(cat "${COUNTER_FILE}" 2>/dev/null || echo 0)"
    # Sanitize: must be a non-negative integer
    if ! [[ "${retries}" =~ ^[0-9]+$ ]]; then
        retries=0
    fi
fi

retries=$((retries + 1))
log "rootfs is read-only (attempt ${retries}/${MAX_RETRIES})"

# Persist the incremented counter to /boot (FAT32, writable even when rootfs is RO).
printf '%d\n' "${retries}" > "${COUNTER_FILE}" 2>/dev/null || true

if [[ "${retries}" -gt "${MAX_RETRIES}" ]]; then
    log "exceeded max attempts (${MAX_RETRIES}); staying on read-only rootfs for manual repair"
    # Leave the counter file as a breadcrumb.
    exit 0
fi

log "rebooting in ${DELAY_SEC}s to allow filesystem check/repair"
sleep "${DELAY_SEC}"

if [[ "${PISTOMP_RO_RECOVERY_NO_REBOOT:-}" == "1" ]]; then
    log "NO_REBOOT=1: would reboot now; exiting for test"
    exit 0
fi

# Sync what we can, then reboot. systemctl may not work if /var is read-only,
# so use the kernel sysrq reboot trigger as a reliable fallback.
sync || true
if systemctl reboot 2>/dev/null; then
    exit 0
fi
log "systemctl reboot failed, using sysrq"
echo b > /proc/sysrq-trigger 2>/dev/null || true

# Should not be reached
exit 1