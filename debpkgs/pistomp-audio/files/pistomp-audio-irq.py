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

DMA_CLASS = "/sys/class/dma"  # dmaengine class directory
I2S_SUFFIX = ".i2s"  # sysfs slave-link target of an i2s device
CHANNEL_SEP = "chan"  # sysfs channel names look like "dma0chan4"
MASK_PROPERTY = "brcm,dma-channel-mask"  # present on bcm2835 controllers only
IRQ_LABEL = "DMA IRQ"  # action name that every bcm2835 DMA channel uses
RTIRQ_INIT = "/etc/init.d/rtirq"


def log(*a):
    """Print a message with the audio-irq label."""
    print("[audio-irq]", *a, flush=True)


def die(msg):
    """Print a stop message. Exit with an error code."""
    print("[audio-irq] STOP:", msg, file=sys.stderr)
    sys.exit(1)


def read_u32s(path):
    """Read a device-tree property as big-endian 32-bit words."""
    with open(path, "rb") as f:
        raw = f.read()
    return [struct.unpack(">I", raw[i : i + 4])[0] for i in range(0, len(raw), 4)]


def find_audio_channels():
    """Find the DMA channels that the i2s device owns."""
    audio = {}
    for c in glob.glob(DMA_CLASS + "/*chan*"):
        slave = os.path.realpath(c + "/slave")
        if not os.path.exists(slave):
            continue
        if slave.endswith(I2S_SUFFIX):
            audio[os.path.basename(c)] = os.path.basename(slave)
    return audio


def chan_index(chan):
    """Read the sysfs channel number out of a channel name."""
    return int(chan.rsplit(CHANNEL_SEP, 1)[1])


def wait_for_audio_channels():
    """Find the i2s DMA channels. Wait for a slow sound-card probe."""
    audio = {}
    for attempt in range(RETRY_SECONDS + 1):
        audio = find_audio_channels()
        if len(audio) == 2:
            return audio
        if attempt == 0:
            log("waiting for the i2s DMA channels to appear...")
        time.sleep(1)
    die("expected two .i2s channels, found %d: %r" % (len(audio), sorted(audio)))


def controller_node(channels):
    """Find the device-tree node of the controller that owns the channels."""
    nodes = {os.path.realpath(f"{DMA_CLASS}/{c}/device/of_node") for c in channels}
    if len(nodes) != 1:
        die(f"audio channels belong to different DMA controllers: {sorted(nodes)!r}")
    return nodes.pop()


def channels_of(node):
    """List the sysfs DMA channels of one controller."""
    return sorted(
        os.path.basename(c)
        for c in glob.glob(DMA_CLASS + "/*chan*")
        if os.path.realpath(c + "/device/of_node") == node
    )


def defer_to_rtirq():
    """Start rtirq. Replace this process with it."""
    if DRY:
        log("dry run: would exec %s start" % RTIRQ_INIT)
        sys.exit(0)
    if not os.path.exists(RTIRQ_INIT):
        die(RTIRQ_INIT + " not found")
    os.execv(RTIRQ_INIT, [RTIRQ_INIT, "start"])


def usable_channels(mask, count):
    """List the hardware channels that agree with the sysfs channel count."""
    bits = [i for i in range(16) if mask & (1 << i)]
    # The driver removes channel 0 (reserved, bcm2835-dma.c:40) and, on some
    # SoCs, channel 14 (kept for memcpy, bcm2835-dma.c:41). Which holds is
    # decided by the sysfs count, not by the model string.
    base = [i for i in bits if i != 0]
    candidates = [base]
    if 14 in base:
        candidates.append([i for i in base if i != 14])
    for cand in candidates:
        if len(cand) == count:
            return cand
    die(
        "sysfs channel count %d agrees with no reading of the mask (%r)"
        % (count, [len(c) for c in candidates])
    )


def interrupt_cells(node):
    """Read the number of interrupt cells of the interrupt parent."""
    # #interrupt-cells lives on the interrupt parent, which in sysfs is an
    # ancestor directory of the controller node.
    d = os.path.dirname(node)
    while d.startswith("/sys/firmware/devicetree"):
        p = os.path.join(d, "#interrupt-cells")
        if os.path.exists(p):
            return open(p, "rb").read()[0]
        d = os.path.dirname(d)
    return 2


def interrupt_table(node):
    """Read the interrupt table of the controller and the entry names."""
    cells = read_u32s(os.path.join(node, "interrupts"))
    nints = interrupt_cells(node)
    if not cells or len(cells) % nints:
        die(
            "interrupts property is %d cells, not a multiple of %d"
            % (len(cells), nints)
        )
    entries = [tuple(cells[i : i + nints]) for i in range(0, len(cells), nints)]
    names = []
    names_path = os.path.join(node, "interrupt-names")
    if os.path.exists(names_path):
        names = open(names_path, "rb").read().rstrip(b"\0").split(b"\0")
        names = [n.decode() for n in names]
        if len(names) != len(entries):
            die(
                "interrupt-names has %d entries, table has %d"
                % (len(names), len(entries))
            )
    return entries, names


def hwirq_of(chan, usable, entries, names):
    """Compute the hardware interrupt number of one DMA channel."""
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


def check_not_shared(audio, controller_chans, hwirqs, usable, entries, names):
    """Stop if another channel shares an interrupt with an audio channel."""
    audio_hwirqs = set(hwirqs.values())
    if len(audio_hwirqs) != len(hwirqs):
        die(
            f"the two audio channels resolve to one interrupt: {sorted(hwirqs.values())!r}"
        )
    for chan in controller_chans:
        if chan in audio:
            continue
        hwirq = hwirq_of(chan, usable, entries, names)
        if hwirq in audio_hwirqs:
            die("hwirq %d is shared with non-audio channel %s" % (hwirq, chan))


def dma_interrupt_rows():
    """Map each DMA hardware interrupt number to its Linux interrupt number."""
    # The kernel prints the hwirq in the column after the chip name
    # (kernel/irq/proc.c, show_interrupts).
    rows = []
    with open("/proc/interrupts") as f:
        ncpu = len(f.readline().split())
        hwidx = ncpu + 2
        for line in f:
            if IRQ_LABEL not in line:
                continue
            fld = line.split()
            if (
                len(fld) > hwidx
                and fld[0].rstrip(":").isdigit()
                and fld[hwidx].isdigit()
            ):
                rows.append((int(fld[hwidx]), int(fld[0].rstrip(":"))))
    return rows


def irq_number(hwirq, rows):
    """Find the Linux interrupt number of one hardware interrupt."""
    hits = [n for h, n in rows if h == hwirq]
    if not hits:
        die("hwirq %d not found in /proc/interrupts" % hwirq)
    if len(hits) > 1:
        die("hwirq %d matches %d DMA lines" % (hwirq, len(hits)))
    return hits[0]


def irq_threads(numbers):
    """Find the IRQ threads of the given Linux interrupt numbers."""
    out = subprocess.run(
        ["ps", "-eLo", "tid,comm"], capture_output=True, text=True
    ).stdout
    found = []
    for l in out.splitlines():
        fld = l.split()
        if len(fld) < 2:
            continue
        m = re.match(r"irq/(\d+)-", fld[1])
        if m and int(m.group(1)) in numbers:
            found.append((fld[0], fld[1]))
    if len(found) != len(numbers):
        die(
            "expected %d irq threads for interrupts %r, found %r"
            % (len(numbers), numbers, found)
        )
    return found


def raise_thread(tid, comm):
    """Set the scheduling policy of one IRQ thread to SCHED_FIFO."""
    log("raising %s (pid %s) to SCHED_FIFO %d" % (comm, tid, PRIO))
    if DRY:
        return
    chrt = ["chrt", "-f", "-p", str(PRIO), tid]
    if os.geteuid() != 0:
        chrt = ["sudo"] + chrt
    subprocess.run(chrt, check=True)


def main():
    """Resolve the audio DMA interrupts. Raise their IRQ threads."""
    audio = wait_for_audio_channels()
    log("audio channels (sysfs slave links):", audio)
    node = controller_node(audio)
    log("DMA controller DT node:", node)

    # Branch on the controller's own topology, not on the model string.
    if not os.path.exists(os.path.join(node, MASK_PROPERTY)):
        log(
            "no brcm,dma-channel-mask (not a bcm2835 controller);"
            " deferring to rtirq name matching"
        )
        defer_to_rtirq()
        return

    mask = read_u32s(os.path.join(node, MASK_PROPERTY))[0]
    log(f"channel mask: 0x{mask:04x}")
    controller_chans = channels_of(node)
    usable = usable_channels(mask, len(controller_chans))
    log("usable hardware channels, in allocation order:", usable)

    entries, names = interrupt_table(node)
    log("interrupt table entries:", len(entries))

    hwirqs = {}
    for chan in sorted(audio):
        hwirqs[chan] = hwirq_of(chan, usable, entries, names)
        idx = chan_index(chan)
        log(
            "%s -> index %d -> hw channel %d -> hwirq %d"
            % (chan, idx, usable[idx], hwirqs[chan])
        )

    check_not_shared(audio, controller_chans, hwirqs, usable, entries, names)

    rows = dma_interrupt_rows()
    numbers = {}
    for hwirq in sorted(set(hwirqs.values())):
        numbers[hwirq] = irq_number(hwirq, rows)
        log("hwirq %d -> /proc/interrupts line %d" % (hwirq, numbers[hwirq]))

    for tid, comm in irq_threads(sorted(set(numbers.values()))):
        raise_thread(tid, comm)
    log("done")


if __name__ == "__main__":
    main()
