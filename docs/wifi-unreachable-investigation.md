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
suppression from anything Pi-side. A persistent Pi-side capture is armed —
see `wifi-capture.service` below.

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
