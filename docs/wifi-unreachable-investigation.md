# WiFi: Mac cannot reach the pi-Stomp

A pi-Stomp on WiFi becomes unreachable from a macOS laptop while the device
itself is healthy and reachable from every other client. Three investigation
sessions: 2026-07-18, 2026-08-03, and 2026-08-04. The 2026-08-04 session
captured the failure from **both ends simultaneously** and identified the
mechanism. This document records only what was measured.

## Environment

| | |
| :--- | :--- |
| Device | Raspberry Pi 5, Debian Trixie, `wlan0` MAC `2c:cf:67:85:d5:09`, `192.168.2.152` |
| Client | macOS laptop, `en0`, MAC `f8:4d:89:a4:4f:9a`, `192.168.2.153` |
| Router | Bell Home Hub, SSID `BELL592`, gateway `192.168.2.1` / `c0:3c:04:29:72:dc` |
| BSSID | `c2:3c:04:29:72:d8`, channel 149 (5745 MHz) — both ends associated to it |
| Second affected host | `192.168.2.10`, does not run pi-Stomp |

## Conclusion

**The AP does not bridge unicast frames from other wireless clients to the
Mac.** Everything else works: the Mac reaches every wireless client, the router
reaches the Mac, and broadcast and multicast flow in both directions. Only
`STA → Mac` unicast is dropped.

| Path | Result |
| :--- | :--- |
| Mac → Pi unicast | delivered — confirmed in the Pi's own capture |
| Pi → Mac unicast | **emitted by the Pi, never reaches the Mac's interface** |
| Pi ↔ Mac broadcast / multicast | delivered both ways |
| Router → Mac unicast | delivered, 0% loss throughout |
| Phone → Pi unicast | delivered — the AP bridges other client pairs normally |
| Phone → Mac unicast | **dropped** — a third STA, same result as the Pi |
| Wired Pi → wireless Mac | delivered — via the router, and over a direct cable |

This is **directly observed, not inferred.** A monitor-mode capture on channel
149 from a third MacBook shows the Pi's frames reaching the AP and never being
retransmitted. The AP acknowledges each one at the MAC layer, then discards it
internally — a forwarding decision, not a radio or range problem.

**This is a CPE bug. pi-Stomp, Debian, NetworkManager, and the Pi's radio are
all exonerated.** The fault is not on the device and nothing on the device can
fix it.

Consequences that follow, and that earlier sessions could not explain:

- **Only Mac-side intervention works.** Cycling `en0` forces re-association,
  which rebuilds the AP's forwarding state for that STA. No Pi-side action can
  reach that state.
- **`192.168.2.10` fails identically** — a second wireless client sending to
  the same broken destination.
- **The ~45s working window after wake.** The AP's state for the STA degrades
  some interval *after* re-association rather than being wrong from the start.
- **No v3.0.5 → v3.1.0 mechanism was ever found** because none exists. The
  version correlation is coincidence.
- **A second developer, different router, different country** — a firmware bug
  class, not something specific to this Home Hub.

## How it was established

Mac-side, during the live failure:

```
09:04  ping 192.168.2.152                    100% loss
       arp -an                               COMPLETE, 2c:cf:67:85:d5:09
       ping6 fe80::3b24:783c:ad3:8428%en0    100% loss
```

The ARP entry being **complete** matters: the July signature of an
`(incomplete)` entry is not universal, and its absence does not mean a
different bug. Pi→Mac broadcasts keep the Mac's cache populated even while
unicast is dead.

IPv6 link-local failing alongside IPv4 rules out routing, DHCP, the gateway,
and the `ipsec0` VPN in one shot — a link-local ping is a raw frame to that
MAC.

Pi-side, at the same moment, from `wifi-capture`:

```
09:00:46  f8:4d:89:a4:4f:9a > 2c:cf:67:85:d5:09  ARP Reply 192.168.2.153 is-at …
09:02:41  f8:4d:89:a4:4f:9a > 2c:cf:67:85:d5:09  ICMP echo request
09:04:58  2c:cf:67:85:d5:09 > f8:4d:89:a4:4f:9a  ICMP echo reply
09:05:05  2c:cf:67:85:d5:09 > f8:4d:89:a4:4f:9a  ICMP6 neighbor advertisement ×6
```

The Mac's unicast arrives. The Pi answers. The answers never land.

Mac-side capture filtered to `ether src 2c:cf:67:85:d5:09`, taken while the Pi
was pinging the Mac: 1116 packets seen by the filter, **six matched, every one
multicast or broadcast**. Zero unicast. Same radio, same AP, same second.

The Pi's ARP behaviour shows the resulting loop directly: it unicasts
`who-has .153`, gets nothing, falls back to broadcast, the Mac answers, the
entry goes `REACHABLE`, unicast resumes, and dies again.

Pi-side stack, checked and clean:

```
ip route get 192.168.2.153   → dev wlan0 src 192.168.2.152
ip rule                      → 32765: from 192.168.2.152 lookup 200
table 200                    → mirrors main; does not diverge
nft list ruleset             → empty
rp_filter                    → 2 (loose); irrelevant to egress
ip neigh 192.168.2.153       → REACHABLE
```

## What restores it

On the **Mac**, not the Pi:

```bash
sudo ifconfig en0 down && sleep 3 && sudo ifconfig en0 up
```

Confirmed three times. Flushing DNS (`dscacheutil -flushcache`,
`killall -HUP mDNSResponder`) has no effect, and `sudo arp -a -d` alone has no
effect. On the device side, nothing has ever restored it — consistent with the
conclusion, since the broken state lives in the AP and is keyed to the Mac's
association.

Changing the Mac's IP while **staying associated** does not restore it either:

```bash
sudo ipconfig set en0 MANUAL 192.168.2.160 255.255.255.0   # still 100% loss
sudo ipconfig set en0 DHCP                                 # restore
```

Weak evidence, and recorded with that caveat: the drop is keyed to the
destination MAC, which this test does not change, so a MAC-keyed fault predicts
the same result. It rules out only an AP-side IP↔MAC mapping table as the sole
mechanism. Note `MANUAL` with just IP and mask installs no default route — the
loss of internet during that test is the command's doing, not a symptom. The
discriminating version needs a *different MAC* on the same Mac, e.g. a USB WiFi
adapter; Apple Silicon will not spoof `en0`.

## Mitigations

For users, in order of preference:

1. **Ethernet on the pi-Stomp.** Confirmed immune, both wired to the router
   with the Mac on WiFi, and over a direct cable. The AP's wired→wireless
   bridge path is unaffected by the fault; only STA→STA is broken.
2. **Toggle WiFi off and on** on the *computer* — not the pi-Stomp. Five
   seconds, and it is the whole fix. This is the support answer.
3. **The device hotspot** (`pistomp-hotspot`) bypasses the router entirely.

Nothing shipped on the device can fix this. The AP already receives and ACKs
our frames continuously throughout the failure and drops them anyway, so
gratuitous ARP, keepalives, and NM configuration changes are all inert. The
device keeps working throughout — audio, footswitches and LCD are unaffected,
since pi-Stomp's only network surface is a localhost WebSocket. What breaks is
one client's access to the web UI, and only that client.

## Ruled out by direct measurement

| Hypothesis | Contradicted by |
| :--- | :--- |
| WiFi power save on the Pi | `iw dev wlan0 get power_save` → off, two separate failing boots |
| MAC randomization on the Pi | Permanent MAC, `wifi.scan-rand-mac-address=no` |
| Duplicate / competing NM profiles | Only `preconfigured` and `pistomp-hotspot` exist |
| Hotspot AP/client flapping | `wifi-hotspot` disabled and inactive |
| RT / CPU starvation | SCHED_OTHER, 5.5% CPU, load 0.54 |
| mDNS / name resolution | Name resolved correctly through the entire outage |
| The pi-Stomp application | Only network surface is `nmcli` subprocesses and a **localhost** WebSocket |
| Cross-radio / band steering | Both ends on the same BSSID and channel during the failure |
| macOS firewall | `State = 0`, stealth off |
| Pi-side routing / policy tables | `ip route get` correct; table 200 mirrors main |
| Pi-side firewall | `nft list ruleset` empty |
| Pi stale ARP/ND for the Mac | `ip neigh` → `REACHABLE` while the failure was live |
| IP address conflict | Router's table maps `.153 → f8:4d:89:a4:4f:9a` correctly |
| Mac's receive path / VPN / pf | Router→Mac unicast delivered at 0% loss throughout |
| Symmetric client isolation | Mac→Pi unicast **is** delivered; phone→Pi works |
| Name resolution, DNS caching | `dns-sd` returned correct A and AAAA during the outage |

Two tests worth keeping for their method:

**Static ARP to the gateway.** `route add -host … 192.168.2.1` does *not* work
on macOS here — the pre-existing cloned `ifscope`/`LLINFO` host route wins, and
`tcpdump` shows frames still addressed to the Pi. Force it at L2 instead:

```bash
sudo arp -S 192.168.2.152 c0:3c:04:29:72:dc   # -S overwrites; -s refuses
ping -c 5 192.168.2.152
sudo arp -d 192.168.2.152                     # always undo
```

The router answered with `ICMP Redirect Host`, proving it received and resolved
the packet. The ping still failed — because the Pi's *reply* takes the broken
path regardless of how the request arrived. **Routing around the forward path
cannot test the return path.**

**Third-client control.** During the failure, phone → Pi succeeds and phone →
Mac times out. A third, unrelated wireless client hits the same wall, so the
fault is **per-destination-STA, not pairwise**: the AP's forwarding entry for
the Mac is broken for all bridged wireless traffic. Controlled — the same app
pings `192.168.2.1` and `192.168.2.152` successfully, so the timeout against
`.153` is not a missing local-network permission.

## Controlled non-reproductions

Two valid sleep/wake cycles on 2026-08-03, both clean throughout:

| Run | Sleep | Pi boot → Mac wake | Result |
| :--- | :--- | :--- | :--- |
| 23:02 | 590s | 264s | 0% loss, clean 3 min |
| 23:18 | 635s | **27s** | 0% loss, clean 4m45s (Pi uptime 30→313s) |

The second deliberately matched the failing run's short boot-to-wake interval
and spanned the 107s onset mark. **A short boot-to-wake interval is not
sufficient to trigger the bug.**

A third attempt was void: the Mac slept only 34s (`pmset -g log` confirms), too
short to drop association on AC with `TCPKeepAlive=active`. Verify the probe's
`WAKE DETECTED — slept Ns` banner reports 600s+ before believing any run.

`awdl0` was `active` in both the failure and both controls, so it does not
discriminate.

## Failure onset is not at wake

In the one instrumented failure, the Mac woke and reached the Pi normally for
~45s before losing it:

```
19:07:31  Pi boots
19:08:18  Mac wakes                (Pi uptime  47s)
19:08:39  ssh "Connection established"
19:09:02  v4=UP  sshbyname=OK
19:09:18  FAIL begins              (Pi uptime 107s)   — continues ~8 min
```

Nothing changed on the Mac between 19:09:02 and 19:09:18.

## The v3.1.0 attribution is unsupported

A full v3.0.5 vs v3.1.0 audit of every external command either version runs
found **no mechanism**, and the 2026-08-04 measurements confirm there is none
to find. Retained because the audit is still the reason not to revisit it.

v3.0.5's periodic footprint was `wpa_cli -i wlan0 status` +
`systemctl is-active wifi-hotspot` every 5s — both pure reads. It ran nothing
state-changing on any timer, poll loop, or UI refresh. v3.1.0's 5s tick is
heavier (N+3 `nmcli` invocations) but equally read-only. On an NM image
`wpa_cli` likely failed outright, making v3.0.5's footprint smaller still.

Three real behavioural deltas exist; all are excluded on the affected device:

| Delta | Excluded by |
| :--- | :--- |
| v3.1.0 mints a new profile + UUID per scanned join (`ops.resolve_unique_name`) | Device runs `preconfigured`, `e957098c…`; no minted profiles |
| Hotspot moved from the systemd unit to NM | `wifi-hotspot` disabled + inactive; single `pistomp-hotspot` |
| `LimitRTPRIO=95` added to the service unit | Process is SCHED_OTHER, rtprio unset, 5.7% CPU |

Scanning is not a factor. `WifiMenu.tick()` repeats scans only while the
"Nearby networks" list is the current panel, paced by `RESCAN_INTERVAL_S`
(10s); the root menu scans once on open. The bug occurs with the menu closed.

## The monitor-mode capture

This is what turns the conclusion from elimination into observation. A third
MacBook sniffed channel 149 while the Pi pinged the Mac.

Capture: Option-click the WiFi menu → **Open Wireless Diagnostics** → **Window
→ Sniffer** → channel 149, width 80 MHz. Writes a pcap to `/var/tmp/`. The
`airport -c149` binary was removed in macOS 14.4+, so the GUI is the reliable
way to pin the channel; a sniffer on the wrong channel yields a clean, empty,
entirely misleading result. Stop the sniffer before reading the file or
`tcpdump` reports a truncated dump.

WPA encrypts the payload, but 802.11 addresses stay in clear, which is all this
needs. Generate identifiable traffic from the Pi — `ping -c 30 -s 1400 -i 1
192.168.2.153`.

```bash
# Pi → AP (to-DS). Nine frames, 1s cadence, MCS 9 at −67 dBm, IV incrementing.
tcpdump -r /var/tmp/*.pcap -e -n \
  'wlan addr2 2c:cf:67:85:d5:09 and wlan addr3 f8:4d:89:a4:4f:9a'

# AP → Mac carrying them (from-DS). ZERO frames.
tcpdump -r /var/tmp/*.pcap -e -n \
  'wlan addr1 f8:4d:89:a4:4f:9a and wlan addr3 2c:cf:67:85:d5:09'

# Control: every frame the AP sent to the Mac, any source. 5014 frames,
# including SA:c0:3c:04:29:72:dc — the gateway's unicast — plus RTS/CTS.
tcpdump -r /var/tmp/*.pcap -e -n 'wlan addr1 f8:4d:89:a4:4f:9a' | wc -l
```

**The control is not optional.** 802.11ac beamforming lets a sniffer legitimately
miss frames directed elsewhere, so an empty downlink result means nothing
without evidence the sniffer hears that direction at all. At 5014 frames it
plainly does.

No retries and a steadily advancing IV on the uplink frames mean the AP
**acknowledged** each one. It accepts the frame at the MAC layer and discards
it internally: a forwarding decision, not a radio or range problem.

## Getting a shell during the outage

The device is unreachable from the Mac by definition, so the Mac cannot read
the capture. Earlier revisions of this document specified `ssh
pistomp@pistomp.local` for exactly that job, which cannot work.

Use a third host as a jump host. The private key never leaves the Mac:

```bash
ssh -J user@<other-host-ip> pistomp@192.168.2.152
```

Use the Pi's IP for the final hop — the name is resolved on the jump host.
Windows 11 needs the OpenSSH server feature first (admin PowerShell):

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service -Name sshd -StartupType Automatic; Start-Service sshd
```

Password auth is disabled on the Pi — `Permission denied (publickey)` from
another host enumerates the accepted methods and confirms it. Alternatives if
no jump host is available: ethernet to the Pi (a separate L2 path that leaves
`wlan0` and its capture untouched), or HDMI + USB keyboard.

## Instrumentation

`wifi-capture.service` runs `/usr/local/bin/wifi-capture.sh`, is enabled across
reboots, and writes to `/var/log/wifi-capture/<date>-<bootid>/`:

| File | Contents |
| :--- | :--- |
| `wlan0.pcapN` | 8 × 20 MB ring: `arp or rarp or icmp or icmp6 or port 5353` |
| `state.log` | every 30s: `ip neigh`, BSSID, signal, power save, uptime |

`state.log` originally lived at `$DIR/state.log`, not inside the per-boot `$RUN`
directory — a single file accumulating across every boot, while the pcap ring
was correctly per-run. Looking for it beside the pcap found nothing and it was
briefly mistaken for a dead state loop; the loop was always running. Fixed
2026-08-04 (`STATE=$RUN/state.log`); the accumulated history is preserved as
`state.log.pre-20260804-fix`.

What it gives: continuous confirmation that the Pi held one BSSID at −42 to
−46 dBm with power save off for the whole failure, and a cheap fingerprint —
the neighbour entry for the Mac cycles `REACHABLE → STALE → DELAY → PROBE →
FAILED` every 30s during the fault, versus stable `REACHABLE` when healthy.

What it does not give: the onset. The Pi rebooted mid-failure and the entry was
already churning at 65s uptime. The Pi's clock is the wrong one regardless —
the AP's broken state is keyed to the *Mac's* association, so onset must be
measured from the Mac's wake. The 45s figure still rests on the single July
run.

The ring restarts at `.pcap0` every run, so each boot gets its own
subdirectory; the newest 12 are kept. The `boot_id` suffix keeps names unique
when NTP later corrects the clock backwards. Debian's `tcpdump` drops to user
`tcpdump` and cannot write under `/var/log`; the script passes `-Z root`. The
filter deliberately excludes SSH, or the capture's own control traffic rotates
the evidence out of the ring.

Evidence from the 2026-08-04 failure is archived at
`~/wifi-evidence.tar.gz` on the Mac (48 KB,
`20260804-000829-b359b0a3/wlan0.pcap0`).

Removal:

```bash
sudo systemctl disable --now wifi-capture
sudo rm -rf /etc/systemd/system/wifi-capture.service /usr/local/bin/wifi-capture.sh /var/log/wifi-capture
```

## Open questions

1. **Why does the AP's forwarding state for the Mac's STA break?** The trigger
   is unknown. It follows re-association after a long sleep by ~45s in the one
   instrumented case, but two controlled sleep/wake cycles did not reproduce
   it. This is the only question left that bears on a fix.
2. **Is the second developer's instance the same fault?** Never instrumented.
   The both-ends capture procedure above would settle it.

**Not a misapplied setting.** The Home Hub 4000 exposes no client-isolation
feature, so there is nothing to un-toggle and no configuration fix. Whatever
produces the drop is internal to the firmware and not user-reachable. Mesh is
excluded too: the BSSID in use, `c2:3c:04:29:72:d8`, is the hub's own radio —
same base address as the gateway's `c0:3c:04:29:72:dc`, differing in the
locally-administered bit — so no WiFi pod was in the path.

**Why cycling WiFi works** is unmeasured; the AP is a black box. The failure
sorts by *source*, not destination — traffic the AP originates itself reaches
the Mac fine, traffic it must bridge from a wireless client does not. That
points at the client-to-client fast path (a hardware forwarding or flow-offload
table) rather than the slow path the router's own stack uses. Deauthentication
tears down the whole per-STA context — association ID, forwarding entries,
power-save bookkeeping, key state — and reconnect rebuilds it. That fits the
evidence that every IP-level remedy fails and only the 802.11-level one works,
but it remains a hypothesis.

## Diagnostics

```bash
# Which BSSID / channel each end is on
nmcli -f IN-USE,BSSID,CHAN,FREQ,SIGNAL dev wifi list --rescan no | grep '^\*'   # Pi
iw dev wlan0 link                                                              # Pi
system_profiler SPAirPortDataType | grep -E 'Channel|Signal|PHY Mode'          # macOS

# The decisive pair — run simultaneously, both ends
sudo tcpdump -i en0 -n -e -c 20 'ether src 2c:cf:67:85:d5:09'   # Mac
ping -c 5 192.168.2.153                                         # Pi

ip neigh show                        # Pi: REACHABLE is not exculpatory
arp -an | grep 192.168.2.152         # macOS; may be COMPLETE and still fail
```

macOS suppresses ARP retries for ~20s after a failed entry — `sudo arp -d <ip>`
before capturing, or the capture will contain nothing. Read a `tcpdump` output
file only after the process exits; otherwise output buffering makes it appear
empty.
