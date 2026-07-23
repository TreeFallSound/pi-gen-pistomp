#!/bin/bash
# Replace the factory SSH host keys baked into the image with per-device ones.
#
# Every card flashed from a given image ships identical host keys (they are
# generated once, at build time, by stage2/01-sys-tweaks/01-run.sh). That is
# deliberate -- it guarantees sshd can always start, so a headless appliance is
# never unreachable -- but it means any pi-Stomp can impersonate any other until
# these are replaced. This runs once, before sshd, and swaps them out.
#
# Design constraints, learned the hard way (see CLAUDE.md "SSH host keys"):
#
#   1. Never delete a key before its replacement exists on disk. An earlier
#      image rm'd the host keys at build time and relied on a boot-time unit to
#      regenerate them; when that unit didn't run, sshd had no keys, refused to
#      start, and the device was unreachable with no console.
#   2. Trigger on a self-clearing stamp file, NOT ConditionFirstBoot= and not
#      anything derived from /etc/machine-id. First-boot detection is exactly
#      what misfired last time (machine-id was rm'd rather than truncated, so
#      every boot looked like the first).
#   3. Fail soft. If anything here goes wrong we keep the factory keys, leave
#      the stamp in place so the next boot retries, and exit non-zero to get it
#      into the journal. Degraded means "shared key", never "no key".
set -euo pipefail

STAMP="/etc/ssh/.factory-host-keys"

# Not a factory image, or we already ran. Nothing to do.
[[ -e "${STAMP}" ]] || exit 0

# Sweep any staging dir orphaned by an earlier crash or power cut. They are
# inert (nothing reads them) but there is no reason to accumulate them.
rm -rf /etc/ssh/.hostkeys.*

# Staging dir lives under /etc/ssh so the final mv is a same-filesystem
# rename(2), i.e. atomic per key.
STAGE="$(mktemp -d /etc/ssh/.hostkeys.XXXXXX)"
trap 'rm -rf "${STAGE}"' EXIT

# `ssh-keygen -A -f DIR` treats DIR as a root prefix and writes to DIR/etc/ssh,
# but it will not create that path itself -- it just fails per key if it is
# missing. Make it first.
GENERATED="${STAGE}/etc/ssh"
mkdir -p "${GENERATED}"
ssh-keygen -A -f "${STAGE}" >/dev/null

shopt -s nullglob
new_keys=("${GENERATED}"/ssh_host_*_key)
if (( ${#new_keys[@]} == 0 )); then
    echo "regenerate-ssh-host-keys: ssh-keygen -A produced no keys;" \
         "keeping the factory keys and leaving ${STAMP} for the next boot." >&2
    exit 1
fi

# Every key we are about to install must have its public half, or sshd will
# refuse to load it. Check before touching /etc/ssh.
for key in "${new_keys[@]}"; do
    if [[ ! -s "${key}" ]] || [[ ! -s "${key}.pub" ]]; then
        echo "regenerate-ssh-host-keys: ${key} incomplete;" \
             "keeping the factory keys and leaving ${STAMP} for the next boot." >&2
        exit 1
    fi
done

for key in "${new_keys[@]}"; do
    name="$(basename "${key}")"
    chmod 600 "${key}"
    chmod 644 "${key}.pub"
    chown root:root "${key}" "${key}.pub"
    mv -f "${key}"     "/etc/ssh/${name}"
    mv -f "${key}.pub" "/etc/ssh/${name}.pub"
done

# Only now, with new keys durably in place, retire the trigger.
sync
rm -f "${STAMP}"

echo "regenerate-ssh-host-keys: installed ${#new_keys[@]} per-device host key(s)."
