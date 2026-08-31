#!/usr/bin/env python3
"""pi-Stomp audio DMA IRQ resolver (one service, every board).

The walk is the same everywhere: find the DMA channels that the i2s device
owns through the sysfs slave links, and follow them to the DMA controller's
device-tree node. The controller's own topology then picks the branch:

- The controller node carries brcm,dma-channel-mask (bcm2835-dma,
  Raspberry Pi 2/3/4). Every channel asks for its interrupt with the same
  name "DMA IRQ" (bcm2835-dma.c:844), so name matching cannot tell the
  audio lines from the SD card and LCD lines. Derive them instead:
  channel index -> hardware channel -> interrupt table entry -> hwirq ->
  /proc/interrupts line, then raise the two irq/N-* threads to SCHED_FIFO
  90 (the priority the old rtirq.conf named).

- The controller node carries no mask (Raspberry Pi 5, RP1 dw-axi-dmac).
  Defer to /etc/init.d/rtirq unchanged; its name list raises the single
  RP1 DMA thread. This branch behaves exactly as the rtirq.service of
  earlier images did.

Every step is printed so a person can check the derivation by eye.

Stops and changes nothing (bcm2835 branch) if:
- the number of channels in sysfs does not agree with the channel mask,
- the interrupt table does not agree with interrupt-names,
- a calculated hardware interrupt is not in /proc/interrupts,
- the two audio channels resolve to one interrupt, or any other channel
  of the controller resolves to an audio interrupt (shared).

Run with --dry-run to derive and report without changing priorities.
"""

import glob
import os
import re
import struct
import subprocess
import sys
import time

DRY = "--dry-run" in sys.argv
PRIO = 90
# The sound card allocates its channels when it probes, at boot, before
# jack.service. The retry loop only guards against a slow probe.
RETRY_SECONDS = 30


def log(*a):
    print("[audio-irq]", *a, flush=True)


def die(msg):
    print("[audio-irq] STOP:", msg, file=sys.stderr)
    sys.exit(1)


def read_u32s(path):
    with open(path, "rb") as f:
        raw = f.read()
    return [struct.unpack(">I", raw[i : i + 4])[0] for i in range(0, len(raw), 4)]


# 1. Channels owned by the i2s device (dmaengine sysfs slave links)
def find_audio_channels():
    audio = {}
    for c in glob.glob("/sys/class/dma/*chan*"):
        try:
            slave = os.path.realpath(c + "/slave")
        except OSError:
            continue
        if not os.path.exists(slave):
            continue
        if slave.endswith(".i2s"):
            audio[os.path.basename(c)] = os.path.basename(slave)
    return audio


audio = {}
for attempt in range(RETRY_SECONDS + 1):
    audio = find_audio_channels()
    if len(audio) == 2:
        break
    if attempt == 0:
        log("waiting for the i2s DMA channels to appear...")
    time.sleep(1)
if len(audio) != 2:
    die("expected two .i2s channels, found %d: %r" % (len(audio), sorted(audio)))
log("audio channels (sysfs slave links):", audio)

# 2. DMA controller DT node of those channels
nodes = {os.path.realpath(f"/sys/class/dma/{c}/device/of_node") for c in audio}
if len(nodes) != 1:
    die(f"audio channels belong to different DMA controllers: {sorted(nodes)!r}")
node = nodes.pop()
log("DMA controller DT node:", node)


def prop(name):
    return os.path.join(node, name)


# 3. Branch on the controller's own topology, not on the model string.
if not os.path.exists(prop("brcm,dma-channel-mask")):
    log(
        "no brcm,dma-channel-mask (not a bcm2835 controller);"
        " deferring to rtirq name matching"
    )
    if DRY:
        log("dry run: would exec /etc/init.d/rtirq start")
        sys.exit(0)
    if not os.path.exists("/etc/init.d/rtirq"):
        die("/etc/init.d/rtirq not found")
    os.execv("/etc/init.d/rtirq", ["/etc/init.d/rtirq", "start"])

# 4. Channel mask, and the sysfs channels of this controller only
mask = read_u32s(prop("brcm,dma-channel-mask"))[0]
log(f"channel mask: 0x{mask:04x}")

controller_chans = sorted(
    os.path.basename(c)
    for c in glob.glob("/sys/class/dma/*chan*")
    if os.path.realpath(c + "/device/of_node") == node
)

bits = [i for i in range(16) if mask & (1 << i)]
# The driver removes channel 0 (reserved, bcm2835-dma.c:40) and, on some
# SoCs, channel 14 (kept for memcpy, bcm2835-dma.c:41). Which holds is
# decided by the sysfs count, not by the model string.
candidates = [[i for i in bits if i != 0]]
if 14 in candidates[0]:
    candidates.append([i for i in candidates[0] if i != 14])
usable = None
for cand in candidates:
    if len(cand) == len(controller_chans):
        usable = cand
        break
if usable is None:
    die(
        "sysfs channel count %d agrees with no reading of the mask (%r)"
        % (len(controller_chans), [len(c) for c in candidates])
    )
log("usable hardware channels, in allocation order:", usable)

# 5. Interrupt table. #interrupt-cells lives on the interrupt parent,
# which in sysfs is an ancestor directory of the controller node.
nints = None
d = os.path.dirname(node)
while d.startswith("/sys/firmware/devicetree"):
    p = os.path.join(d, "#interrupt-cells")
    if os.path.exists(p):
        nints = open(p, "rb").read()[0]
        break
    d = os.path.dirname(d)
if nints is None:
    nints = 2
cells = read_u32s(prop("interrupts"))
if not cells or len(cells) % nints:
    die("interrupts property is %d cells, not a multiple of %d" % (len(cells), nints))
entries = [tuple(cells[i : i + nints]) for i in range(0, len(cells), nints)]
log("interrupt table entries:", len(entries))

names = []
if os.path.exists(prop("interrupt-names")):
    names = open(prop("interrupt-names"), "rb").read().rstrip(b"\0").split(b"\0")
    names = [n.decode() for n in names]
    if len(names) != len(entries):
        die("interrupt-names has %d entries, table has %d" % (len(names), len(entries)))


# 6. sysfs index -> hardware channel -> table entry -> hwirq
def chan_index(name):
    return int(name.rsplit("chan", 1)[1])


def hwirq_of(chan):
    idx = chan_index(chan)
    if idx >= len(usable):
        die("%s: sysfs index %d beyond usable channel list %r" % (chan, idx, usable))
    hw = usable[idx]
    if hw >= len(entries):
        die("hardware channel %d has no interrupt entry" % hw)
    if names and names[hw] != "dma%d" % hw:
        die("interrupt table position %d is named %r, not dma%d" % (hw, names[hw], hw))
    bank, bit = entries[hw][0], entries[hw][1]
    return (bank << 5) | bit  # irq-bcm2835.c:52


hwirqs = {}
for chan in sorted(audio):
    hwirqs[chan] = hwirq_of(chan)
    idx = chan_index(chan)
    log(
        "%s -> index %d -> hw channel %d -> hwirq %d"
        % (chan, idx, usable[idx], hwirqs[chan])
    )

# Refuse a shared interrupt: the two audio channels must land on two
# distinct hwirqs, and no other channel of this controller may land on
# either of them (Pi 3 channels 11-14 and Pi 4 channels 9+10 share).
if len(set(hwirqs.values())) != 2:
    die(f"the two audio channels resolve to one interrupt: {sorted(hwirqs.values())!r}")
audio_hwirqs = set(hwirqs.values())
for chan in controller_chans:
    if chan in audio:
        continue
    if hwirq_of(chan) in audio_hwirqs:
        die("hwirq %d is shared with non-audio channel %s" % (hwirq_of(chan), chan))

# 7. hwirq -> /proc/interrupts line. The kernel prints the hwirq in the
# column after the chip name (kernel/irq/proc.c, show_interrupts).
with open("/proc/interrupts") as f:
    ncpu = len(f.readline().split())
    rows = []
    for line in f:
        fld = line.split()
        hwidx = ncpu + 2
        if len(fld) > hwidx and fld[0].rstrip(":").isdigit() and fld[hwidx].isdigit():
            rows.append((int(fld[hwidx]), int(fld[0].rstrip(":")), line))

lines = {}
for h in sorted(audio_hwirqs):
    hits = [r for r in rows if r[0] == h and "DMA IRQ" in r[2]]
    if not hits:
        die("hwirq %d not found in /proc/interrupts" % h)
    if len(hits) > 1:
        die("hwirq %d matches %d DMA lines" % (h, len(hits)))
    lines[h] = hits[0][1]
    log("hwirq %d -> /proc/interrupts line %d" % (h, lines[h]))

# 8. raise the irq/N-* threads to SCHED_FIFO 90
targets = sorted(set(lines.values()))
out = subprocess.run(
    ["ps", "-eLo", "tid,comm,rtprio"], capture_output=True, text=True
).stdout
tids = []
for l in out.splitlines():
    fld = l.split()
    if len(fld) >= 2:
        m = re.match(r"irq/(\d+)-", fld[1])
        if m and int(m.group(1)) in targets:
            tids.append((fld[0], fld[1]))
if len(tids) != len(targets):
    die(
        "expected %d irq threads for lines %r, found %r" % (len(targets), targets, tids)
    )
for tid, comm in tids:
    log("raising %s (pid %s) to SCHED_FIFO %d" % (comm, tid, PRIO))
    if DRY:
        continue
    chrt = ["chrt", "-f", "-p", str(PRIO), tid]
    if os.geteuid() != 0:
        chrt = ["sudo"] + chrt
    subprocess.run(chrt, check=True)

log("done")
