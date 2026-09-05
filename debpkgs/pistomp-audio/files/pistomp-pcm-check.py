#!/usr/bin/env python3
"""pi-Stomp PCM bind check (repairs a silently broken sound card).

sound/soc/soc-core.c binds the CPU DAI and the codec DAI with a deferred
probe, but it binds the platform half with no defer at all:

    for_each_link_cpus(...)    if (!snd_soc_find_dai(cpu))   goto _err_defer;
    for_each_link_codecs(...)  if (!snd_soc_find_dai(codec)) goto _err_defer;
    for_each_link_platforms(dai_link, i, platform)
            for_each_component(component)
                    ... snd_soc_rtd_add_component(rtd, component);

bcm2835_i2s_probe() registers the CPU DAI component first and the generic
dmaengine PCM component seven lines later. A machine driver that matches
its platform by of_node alone - iqaudio-codec.c does, and so do the other
bcm cards - therefore matches the CPU DAI component if it binds inside
that window. The CPU DAI component carries no pcm_construct and no open,
so runtime->hw is never filled, and every open() of the PCM returns
EINVAL. Nothing is printed to the kernel log. The card still enumerates,
aplay -l still lists it, and the DMA channels still hold their sysfs
slave links, so the fault is invisible until JACK fails to start.

Two routes reach that state:

- At boot the machine driver defers through the driver core, whose retry
  runs on a workqueue. The codec completing its bind triggers that
  worker, which can re-probe the machine driver on another CPU while
  bcm2835_i2s_probe() sits between its two registrations.
- At runtime, removing a component puts an instantiated card on ASoC's
  unbind_card_list, and the next snd_soc_add_component() rebinds it
  synchronously - on the CPU DAI, before the dmaengine platform exists.

Both end in the same card. One unbind/rebind of the machine driver
repairs it, because by then both components are in component_list and
the platform loop adds every match.

Upstream fixed this class in fsl_sai, fsl_micfil, fsl_esai, fsl_spdif,
fsl_xcvr and fsl_aud2htx (merge 7bd5d979dfdb) and in davinci-mcasp
(d18ca8635db2), each by registering the platform before the CPU DAI.
bcm2835-i2s has never carried that fix; it is still in the original 2013
order in mainline. This script is the userspace counterpart, so deployed
devices are covered over OTA.

Run with --dry-run to report without changing anything.
"""

import errno
import glob
import os
import re
import subprocess
import sys
import time

DRY = "--dry-run" in sys.argv

JACK_DEFAULTS = "/etc/default/jack"
DEFAULT_DEVICE = "hw:0"
SOUND_CLASS = "/sys/class/sound"
PLATFORM_DRIVERS = "/sys/bus/platform/drivers"

# The card is bound during udev coldplug, long before this unit runs. The
# wait only guards against a slow probe.
CARD_WAIT_SECONDS = 30
# The repair is deterministic once both components are registered, so a
# second attempt only covers an unusually slow i2s probe. Every rebind
# leaks one device_node reference in the machine driver (it calls
# of_parse_phandle without a matching of_node_put), so this stays small.
MAX_ATTEMPTS = 3
SETTLE_SECONDS = 2


def log(*a):
    """Print a message with the pcm-check label."""
    print("[pcm-check]", *a, flush=True)


def fail(msg):
    """Print a stop message. Exit with an error code."""
    print("[pcm-check] STOP:", msg, file=sys.stderr, flush=True)
    sys.exit(1)


def jack_device():
    """Read JACK_DEVICE from /etc/default/jack. Fall back to hw:0."""
    try:
        with open(JACK_DEFAULTS) as f:
            text = f.read()
    except OSError:
        return DEFAULT_DEVICE
    m = re.search(r'^\s*JACK_DEVICE\s*=\s*"?([^"\n]*)"?', text, re.M)
    if not m or not m.group(1).strip():
        return DEFAULT_DEVICE
    return m.group(1).strip()


def card_index(device):
    """Turn a JACK device string (hw:0, hw:0,0, hw:NAME) into a card index."""
    spec = device.split(":", 1)[1] if ":" in device else device
    spec = spec.split(",")[0].strip()
    if spec.isdigit():
        return int(spec)
    # Named card: match against each card's id file.
    for path in sorted(glob.glob(SOUND_CLASS + "/card[0-9]*")):
        try:
            with open(path + "/id") as f:
                if f.read().strip() == spec:
                    return int(path.rsplit("card", 1)[1])
        except OSError:
            continue
    return None


def wait_for_card(device):
    """Wait for the card named by `device` to appear. Return its index."""
    deadline = time.time() + CARD_WAIT_SECONDS
    while True:
        idx = card_index(device)
        if idx is not None and os.path.exists("%s/card%d" % (SOUND_CLASS, idx)):
            return idx
        if time.time() >= deadline:
            return None
        time.sleep(1)


def pcm_path(idx):
    """Return the playback PCM device node for a card index."""
    return "/dev/snd/pcmC%dD0p" % idx


def probe_pcm(idx):
    """Open the playback PCM. Return 'ok', 'busy' or 'broken'."""
    path = pcm_path(idx)
    if not os.path.exists(path):
        return "broken"
    try:
        fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    except OSError as e:
        if e.errno == errno.EBUSY:
            # Something already holds the device, so it opened for that
            # client. The card works.
            return "busy"
        if e.errno == errno.EINVAL:
            return "broken"
        log("open %s failed with an unexpected error: %s" % (path, e.strerror))
        return "broken"
    os.close(fd)
    return "ok"


def machine_driver(idx):
    """Find the platform device and driver that own a card.

    Returns (driver_dir, device_name), or None when the card is not a
    platform device. A USB card is not, and it must never be rebound: the
    fault this script repairs is specific to the bcm2835 i2s platform.
    """
    dev = os.path.realpath("%s/card%d/device" % (SOUND_CLASS, idx))
    drv = os.path.realpath(os.path.join(dev, "driver"))
    if not os.path.isdir(drv):
        return None
    if os.path.dirname(drv) != os.path.realpath(PLATFORM_DRIVERS):
        log(
            "card%d is not a platform device (driver %s); leaving it alone" % (idx, drv)
        )
        return None
    if not (os.path.exists(drv + "/bind") and os.path.exists(drv + "/unbind")):
        log("driver %s has no bind/unbind" % drv)
        return None
    return drv, os.path.basename(dev)


def rebind(drv, name):
    """Unbind and rebind one platform device."""
    for action in ("unbind", "bind"):
        with open(os.path.join(drv, action), "w") as f:
            f.write(name)
        time.sleep(1)


def alsa_restore(idx):
    """Restore the mixer levels. A rebind returns the codec to defaults."""
    try:
        subprocess.run(
            ["alsactl", "restore", str(idx)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
            timeout=30,
        )
    except (OSError, subprocess.SubprocessError) as e:
        log("alsactl restore failed: %s (continuing)" % e)


def main():
    device = jack_device()
    log("JACK device is %s" % device)

    idx = wait_for_card(device)
    if idx is None:
        fail("no sound card for %s after %ds" % (device, CARD_WAIT_SECONDS))
    log("card%d found" % idx)

    state = probe_pcm(idx)
    if state in ("ok", "busy"):
        log("%s opens (%s); nothing to do" % (pcm_path(idx), state))
        return 0

    log("%s returns EINVAL: the platform component is not bound" % pcm_path(idx))

    target = machine_driver(idx)
    if target is None:
        fail("cannot repair card%d: no platform driver to rebind" % idx)
    drv, name = target
    log("machine driver is %s, device %s" % (os.path.basename(drv), name))

    if DRY:
        log("dry run: would rebind %s and restore the mixer" % name)
        return 1

    for attempt in range(1, MAX_ATTEMPTS + 1):
        log("rebind attempt %d of %d" % (attempt, MAX_ATTEMPTS))
        try:
            rebind(drv, name)
        except OSError as e:
            log("rebind failed: %s" % e)
            time.sleep(SETTLE_SECONDS)
            continue
        time.sleep(SETTLE_SECONDS)

        # The card number can change across a rebind, so resolve it again.
        idx = wait_for_card(device)
        if idx is None:
            log("card did not come back; retrying")
            continue

        state = probe_pcm(idx)
        if state in ("ok", "busy"):
            log("repaired: card%d %s opens (%s)" % (idx, pcm_path(idx), state))
            alsa_restore(idx)
            log("mixer restored")
            return 0
        log("still broken after attempt %d" % attempt)

    fail("card%d still returns EINVAL after %d rebinds" % (idx, MAX_ATTEMPTS))


if __name__ == "__main__":
    sys.exit(main())
