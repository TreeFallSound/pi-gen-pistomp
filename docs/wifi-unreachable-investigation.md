# WiFi: Mac cannot reach the pi-Stomp

A pi-Stomp on WiFi becomes unreachable from a macOS laptop while the device
itself is healthy and reachable from other clients. Two investigation sessions:
2026-07-18 and 2026-08-03. This document records only what was measured.

## Environment

| | |
| :--- | :--- |
| Device | Raspberry Pi 5, Debian Trixie, `wlan0` MAC `2c:cf:67:85:d5:09`, `192.168.2.152` |
| Client | macOS laptop, `en0`, MAC `f8:4d:89:a4:4f:9a`, `192.168.2.153` |
| Router | Bell Home Hub, SSID `BELL592`, gateway `192.168.2.1` / `c0:3c:04:29:72:dc` |

## What is established

**The failure is unidirectional L2 unreachability, Mac → Pi.** It is not name
resolution and not the pi-Stomp application.

- `pistomp.local` resolved correctly throughout an 11-minute total outage.
- Mac-side `tcpdump`: 11 ARP broadcasts for `.152` and `.10`, zero replies.
  The Mac's ARP entry stays `(incomplete)`.
- Multicast frames *from* `2c:cf:67:85:d5:09` arrive at the Mac during the
  outage. The Pi is transmitting and the Mac is receiving.
- Mac → gateway 0% loss, Mac → `.17` 0% loss, Mac → `.152` and `.10` 100% loss.
- A phone reached the Pi normally at the same moment. The Pi is exonerated.
- Both ends were associated to the **same BSSID `C2:3C:04:29:72:D8`, channel
  149**, during the 2026-08-03 failure.

## What restores it

On the **Mac**, not the Pi:

```bash
sudo ifconfig en0 down && sleep 3 && sudo ifconfig en0 up
```

Confirmed twice. Flushing DNS (`dscacheutil -flushcache`,
`killall -HUP mDNSResponder`) has no effect. `sudo arp -a -d` alone has no
effect. On the device side, nothing tried has ever restored it.

## Ruled out by direct measurement

| Hypothesis | Contradicted by |
| :--- | :--- |
| WiFi power save on the Pi | `iw dev wlan0 get power_save` → off, on two separate failing boots |
| MAC randomization on the Pi | Permanent MAC, `wifi.scan-rand-mac-address=no` |
| Duplicate / competing NM profiles | Only `preconfigured` and `pistomp-hotspot` exist |
| Hotspot AP/client flapping | `wifi-hotspot` disabled and inactive |
| RT / CPU starvation | SCHED_OTHER, 5.5% CPU, load 0.54 |
| NM profile UUID churn changing IPv6 addresses | Device stays on `preconfigured`; UUID never changes |
| mDNS / name resolution | Name resolved correctly through the entire outage |
| The pi-Stomp application | Its only network surface is `nmcli` subprocesses and a **localhost** WebSocket |
| Cross-radio / band steering | Both ends on the same BSSID and channel during the failure |
| macOS firewall | `State = 0`, stealth off |
| Pi-side routing | Table 200 carries `192.168.2.0/24 dev wlan0 scope link` |

`192.168.2.10` was recorded in the July log as a control proving "not client
isolation". It is in fact a **second affected host** — Mac → `.10` also fails.

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

Nothing changed on the Mac between 19:09:02 and 19:09:18. A stale cache or an
aged-out AP forwarding entry would fail immediately on wake, not after a
working window.

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

## The v3.1.0 attribution is unsupported

A full v3.0.5 vs v3.1.0 audit of every external command either version runs
found **no mechanism**. v3.0.5's periodic footprint was `wpa_cli -i wlan0
status` + `systemctl is-active wifi-hotspot` every 5s — both pure reads. It ran
nothing state-changing on any timer, poll loop, or UI refresh: no reconnect, no
reassociate, no `nmcli con up`, no DHCP renew, no interface bounce. v3.1.0's
5s tick is heavier (N+3 `nmcli` invocations) but equally read-only.

This falsifies the "v3.0.5 incidentally emitted gratuitous ARP and masked an
underlying fault" hypothesis. On an NM image `wpa_cli` likely failed outright
(NM runs `wpa_supplicant -u` on D-Bus; the `/run/wpa_supplicant/wlan0` control
socket usually does not exist), making v3.0.5's footprint smaller still.

Three real behavioural deltas exist. All are excluded on the affected device:

| Delta | Excluded by |
| :--- | :--- |
| v3.1.0 mints a new profile + UUID per scanned join (`ops.resolve_unique_name`) | Device runs `preconfigured`, `e957098c…`; no minted profiles |
| Hotspot moved from the systemd unit to NM, so an upgraded device can hold two AP profiles | `wifi-hotspot` disabled + inactive; single `pistomp-hotspot` |
| `LimitRTPRIO=95` added to the service unit | Process is SCHED_OTHER, rtprio unset, 5.7% CPU |

Combined with `192.168.2.10` — which does not run pi-Stomp — failing at the
same moment, **no evidence supports the version correlation.** It rests on
recollection; v3.0.5 was never instrumented.

Scanning is not a factor. `WifiMenu.tick()` repeats scans only while the
"Nearby networks" list is the current panel, paced by `RESCAN_INTERVAL_S`
(10s, above NM's 8s rate limit); the root menu scans once on open. The bug
occurs with the menu closed.

## Open questions

1. **Why did this not occur on release/v3.0.5?** Unexplained. Both v3.0.5 and
   v3.1.0 shipped on the *same* pi-gen image (`v3.0.4`, 2026-04-09) — no OS
   release exists between then and the 3.2 line in July. The only variable is
   the pi-Stomp application, whose network surface is listed above. An A/B does
   not require reflashing; check out the old app version on the device.
2. **Why does it also occur for a second developer on a different router, in a
   different country?** That instance has never been instrumented.

Any correct mechanism must satisfy both.

## Not yet measured

Every capture so far is Mac-side. **Whether the Mac's ARP requests reach the
Pi has never been observed.** That single fact separates AP-side broadcast
suppression from anything Pi-side.

`wifi-capture.service` is armed on the test device to answer it. It runs
`/usr/local/bin/wifi-capture.sh`, is enabled across reboots, and writes to
`/var/log/wifi-capture/`:

| File | Contents |
| :--- | :--- |
| `<date>-<bootid>/wlan0.pcapN` | 8 × 20 MB ring: `arp or rarp or icmp or icmp6 or port 5353` |
| `state.log` | every 30s: `ip neigh`, BSSID, signal, power save, uptime |

The ring restarts at `.pcap0` every run, so each boot gets its own subdirectory
or it would overwrite the boot being investigated; the newest 12 are kept. The
`boot_id` suffix keeps names unique when NTP later corrects the clock backwards.

Debian's `tcpdump` drops to user `tcpdump` and cannot write under `/var/log`;
the script passes `-Z root`. The filter deliberately excludes SSH, or the
capture's own control traffic rotates the evidence out of the ring.

After the next occurrence, **before** cycling the Mac's interface:

```bash
ssh pistomp@pistomp.local '
  D=$(ls -1dt /var/log/wifi-capture/*-*-* | head -1)
  sudo tcpdump -r "$D/wlan0.pcap0" -n -e -tttt' | grep -i 'who-has 192.168.2.152'
```

An ARP request from `f8:4d:89:a4:4f:9a` present in that output means the
broadcast reached the Pi and the failure is Pi-side or return-path. Absent
means the AP never delivered it.

Removal:

```bash
sudo systemctl disable --now wifi-capture
sudo rm -rf /etc/systemd/system/wifi-capture.service /usr/local/bin/wifi-capture.sh /var/log/wifi-capture
```

## Diagnostics

```bash
# Which BSSID / channel each end is on
nmcli -f IN-USE,BSSID,CHAN,FREQ,SIGNAL dev wifi list --rescan no | grep '^\*'   # Pi
system_profiler SPAirPortDataType | grep -E 'Channel|Signal|PHY Mode'          # macOS

ip neigh show                        # ARP/ND state
sudo tcpdump -l -n -e -i wlan0 arp   # do the Mac's requests arrive?
arp -an | grep 192.168.2.152         # macOS; (incomplete) is the signature
```

macOS suppresses ARP retries for ~20s after a failed entry — `sudo arp -d <ip>`
before capturing, or the capture will contain nothing.

Read a `tcpdump` output file only after the process exits; otherwise output
buffering makes it appear empty.
