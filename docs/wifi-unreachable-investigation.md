# WiFi reachable-but-unreachable: 2026-07-18 investigation log

A pi-Stomp on WiFi was intermittently unreachable from a macOS laptop while the
device itself reported a healthy link. This is a record of what was measured and
what changed the outcome. Mechanisms proposed during the session are listed at
the bottom under **Discarded hypotheses** — they are recorded so they are not
re-proposed, not because they are believed.

## Environment

| | |
| :--- | :--- |
| Device | Raspberry Pi 5, Debian Trixie, RT kernel 6.18.36-rpi-v8-rt |
| WiFi | brcmfmac, BCM4345/6, single radio |
| Router | Bell "Home Hub", SSID `BELL592`, LAN MAC `c0:3c:04:29:72:dc` |
| Client | macOS laptop, `en0` WiFi, `en7` USB ethernet |

Router BSSIDs observed for `BELL592`:

| BSSID | Chan | Freq |
| :--- | :--- | :--- |
| `C0:3C:04:29:72:E2` | 1 | 2.4 GHz |
| `C0:3C:04:29:72:E3` | 36 | 5180 MHz |
| `C2:3C:04:29:72:D8` | 149 | 5745 MHz |

## Symptom

`ssh pistomp@pistomp.local` and `ping <wifi IP>` fail from the Mac. Plugging in
ethernet appears not to help; disabling WiFi on the Mac eventually restores
access. Recurs over days, "fixes itself", recurred for a second developer on a
different network in a different country (that instance was never instrumented).

## Measurements

Device-side state during the outage — all of this held while the Mac reported
100% packet loss:

- `assoc=yes`, BSSID unchanged, IP unchanged, `gw_ping=ok`, `inet=ok`
- signal -46 to -50 dBm, no deauth/disassoc in the journal, zero NIC errors
- `wlan0` on its permanent MAC `2c:cf:67:85:d5:09` (no randomization on the Pi)

Packet capture on the Pi's `wlan0` during a failing ping from the Mac:

```
requests in: 9
replies out: 9
```

The Pi received and answered every packet. macOS firewall was confirmed
disabled (`State = 0`, stealth off).

Reachability matrix, taken during one failing window:

| From | To | Result |
| :--- | :--- | :--- |
| Mac | gateway `.1` | 0% loss |
| Mac | Pi `.152` | 100% loss |
| Mac | unrelated host `.10` | 100% loss |
| Pi | gateway `.1` | 0% loss |
| Pi | unrelated host `.10` | 0% loss |
| Pi | Mac `.153` | 100% loss |

Pi-side ARP for the Mac went from `FAILED` to a resolved `lladdr` after Bell's
"Whole Home Wi-Fi" was disabled; unicast to the Mac still failed at that point.

Pi-side routing was checked and is correct — policy table 200 carries
`192.168.2.0/24 dev wlan0 scope link`, so replies are not misrouted via the
gateway:

```
$ ip route show table 200
default via 192.168.2.1 dev wlan0
192.168.2.0/24 dev wlan0 scope link src 192.168.2.152
```

A **static ARP entry** installed on the Pi for the Mac did not restore
connectivity. Note this only corrected the Pi's ARP table; the Mac's was not
touched during that test.

A stale neighbour entry for the Mac's previous randomized MAC was observed on
the Pi: `192.168.2.12 → 56:bb:44:f7:96:3a STALE`.

## Changes made, and what followed

Listed in the order applied. Each entry records only what was observed after it.

| # | Change | Observed after |
| :--- | :--- | :--- |
| 1 | macOS **Private Wi-Fi Address disabled** (MAC `56:bb:…` → `f8:4d:89:a4:4f:9a`, new lease `.153`) | Permanent failure became intermittent: 5/5, then 21/25, then 0/25 |
| 2 | Router rebooted | No improvement; 0 of 6 Mac→Pi requests arrived |
| 3 | Bell **"Whole Home Wi-Fi" disabled** | Pi-side ARP for the Mac resolved; unicast still 100% loss |
| 4 | Pi **pinned** to `C0:3C:04:29:72:E3` (ch 36) | 15/15, 0% loss, 9 ms |
| 5 | Pin removed, Pi returned to `C2:…:D8` (ch 149) | 100% loss again |
| 6 | Pin reapplied | 0% loss; SSH over WiFi worked |
| 7 | — (no device change) | Connectivity lost again while pin was still applied |
| 8 | Mac: `dscacheutil -flushcache` + `killall -HUP mDNSResponder` | No change |
| 9 | Mac: **`sudo arp -a -d`** and **`ifconfig en0 down/up`** | **Connectivity restored** |
| 10 | Pin removed from the device (no forced reconnect) | Pi on `C2:…:D8` ch 149, Mac on ch 149, **0% loss** |

Step 10 is the same BSSID pairing that failed at steps 5 and 7.

## What restored connectivity

On the **Mac**, not the Pi:

```
# no effect on its own
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
sudo arp -a -d

# this restored it
sudo ifconfig en0 down && sleep 3 && sudo ifconfig en0 up
```

The Mac's MAC address changed twice during the period (private → hardware) and
its IP changed with it (`.12` → `.153`).

## Multi-address name resolution

`pistomp.local` resolves to four addresses:

```
169.254.125.193          # eth0 IPv4 link-local
192.168.2.152            # wlan0 IPv4
fddc:13a1:617f:4092:…    # IPv6 ULA
fe80:18::2ecf:67ff:…     # IPv6 link-local
```

Measured: with ethernet plugged, `ssh pistomp.local` selects
`fe80::2ecf:67ff:fe85:d508%en7` — the IPv6 link-local over ethernet — first.

```
debug1: Connecting to pistomp.local [fe80::2ecf:67ff:fe85:d508%en7] port 22
CONNECTED via fe80::8dd:ebff:83c1:b976%eth0 49612 fe80::2ecf:67ff:fe85:d508%eth0 22
```

Consequences observed: SSH succeeded over ethernet while WiFi was unreachable,
and when the ethernet far end was dead `ssh` sat on that candidate rather than
failing over quickly. `ssh` walks `getaddrinfo` candidates serially with a full
TCP timeout each; browsers do not (Happy Eyeballs).

## Diagnostic commands used

```bash
# Which BSSID / channel each end is on
nmcli -f IN-USE,BSSID,CHAN,FREQ,SIGNAL dev wifi list --rescan no | grep '^\*'   # Pi
system_profiler SPAirPortDataType | grep -E 'Channel|Signal|PHY Mode'          # macOS
                                    # macOS redacts BSSID without Location Services

ip neigh show                        # ARP/ND state, look for FAILED or stale entries
ip route show table 200              # multihome policy table
sudo tcpdump -l -n -i wlan0 -e icmp  # confirm packets arrive / replies leave
iw event -t                          # observe scans (nmcli and journal do not show bgscan)

dscacheutil -q host -a name pistomp.local   # what the name actually resolves to
ssh -v pistomp@pistomp.local                # which address ssh picks
```

Capture note: read a `tcpdump` output file only after the process has exited, or
the results are empty due to output buffering.

## Discarded hypotheses

Each of these was asserted during the session and is contradicted by the
measurements above. Recorded to prevent repetition.

| Hypothesis | Contradicted by |
| :--- | :--- |
| AP client isolation | Pi reached host `.10` at 0% loss from the same BSSID |
| Router does not forward client-to-client unicast | Same as above |
| `C2:…:D8` is a mesh-backhaul VAP that carries no client traffic | It served DHCP, gateway and internet, and reached `.10` |
| Intra-BSSID isolation on `C2:…:D8` | Step 10: both ends on ch 149, 0% loss |
| wpa_supplicant 2.10 cross-AKM roaming failure | No disconnect or roam events in the journal |
| `machine-id` churn causing DHCP client-id changes | Capture showed a MAC-based client-id (`Client-ID (61), length 7`) |
| Per-interface mDNS hostnames as a fix | Not how multi-homed devices behave; not pursued |

The BSSID pin (steps 4–6) correlated with recovery twice and then failed at step
7 with the pin still applied. Changing BSSID forces re-association and therefore
new ARP resolution, so it is not independent of step 9.

## Open

- No unattended link failure was ever captured. `wifi-monitor` (a temporary
  debug script added during this session, not a shipped component) logged
  `assoc=yes gw_ping=ok inet=ok` continuously throughout, including during every
  period the device was unreachable. Nothing on the device reports LAN-peer
  reachability.
- The second developer's occurrence was never instrumented; no data links it to
  this one.
- Whether the restored state survives beyond 2026-07-18 is unverified.

## Cleanup left on the test device

```bash
sudo systemctl disable --now wifi-monitor.service
sudo apt-get remove tcpdump
```

Persistent journald was enabled via `~/extras/journal-toggle.sh`; it required a
manual `sudo mkdir -p /var/log/journal` and `sudo journalctl --flush`, which that
script does not do.
