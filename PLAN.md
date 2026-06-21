# pi-gen-pistomp Modernization Plan

## Context

pi-gen-pistomp builds a Raspberry Pi OS (Debian) image for pi-Stomp hardware. It lags behind the parallel `pistomp-arch` project in stability, packaging, UX, and dependency hygiene. The docs (COMPARISON.md, UPGRADE-TRIXIE.md, PACKAGING.md, NETWORKING.md, UX-PARITY.md, PACKAGE-COMPARISON.md) represent a complete blueprint for closing those gaps. The user has chosen: **Trixie first**, hybrid packaging (simple debpkgs here, complex components in TreeFallSound forks), all four tracks in scope.

---

## Part 1 — Trixie Upgrade (foundational, do first)

**Goal:** Switch `RELEASE=bookworm` → `RELEASE=trixie` in `config` and make everything build and boot.

### 1a. config
- `stage2/05-pistomp/02-run.sh`: Change `RELEASE=bookworm` → `RELEASE=trixie` in `config`

### 1b. stage2/04-python/01-run.sh — Python packages
- `rm -rf /usr/lib/python3.11/EXTERNALLY-MANAGED` → `python3.13`
- Drop packages that don't build on 3.12+: `scandir`, `backports.shutil-get-terminal-size`, `pep8`, `flake8`, `coverage`, `sphinx`
- `netifaces==0.10.5` → `netifaces2` (unversioned)
- Unpin: `Pillow`, `mido`, `pyserial`, `docopt`
- Drop `pystache==0.5.4` — not compatible with 3.13; need to audit whether pi-stomp still needs it (it uses Mustache templates — likely replaceable)
- **Do NOT install tornado system-wide.** mod-ui needs tornado 4.3 which is broken on 3.13. It gets its own venv (see 1c).
- Add `pyliblo3` (replaces broken `pyliblo 0.10.0` — Cython 3.x incompatibility)

### 1c. stage2/05-pistomp/02-run.sh — C components
Trixie gives us these **via apt** (no more source builds):
- `python3-lilv`, `liblilv-dev` — drop the entire `lilv-0.24.12` WAF build block
- `jackd2` is available at v1.9.22, but **we still build from source** because we need the `pi-controller-reset.patch` (see Part 2). For now, keep building jack2 from source; Part 3 replaces this with a .deb.

mod-ui needs an isolated Python 3.11 venv (same pattern as pistomp-arch):
```bash
python3.11 -m venv /opt/mod-ui-venv
/opt/mod-ui-venv/bin/pip install tornado==4.3 ...
```
Update the mod-ui.service to use `/opt/mod-ui-venv/bin/python`.

Packages removed in trixie — remove from `stage2/*/00-packages`:
- `pigpio`, `python3-pigpio`, `raspi-gpio`, `policykit-1`, `rcconf`
- `libfluidsynth2` → `libfluidsynth3`
- `usbmount` (broken on trixie — remove or replace)

Also fix the sed hack patching `tornado/httputil.py` — that sed line is targeting the old system tornado install; with mod-ui in its own venv the tornado path changes (or is no longer needed).

### 1d. RT kernel .deb rebuild
The current blobs (`linux-image-6.1.54-rt15-v8+` etc. in `stage2/05-pistomp/files/sys/`) are built against bookworm's initramfs infrastructure and **will not work on trixie**. Two options:
- **Short-term:** Find/build a trixie-compatible RT kernel .deb (same approach, new build target). Check if raspberrypi-kernel-rt is in trixie apt, or rebuild against trixie's initramfs.
- **Long-term:** Part 3 (packaging infra) will set up CI to build this cleanly.

For initial Trixie unblock, check whether the 6.12.9 Pi5 kernel works on trixie as-is (initramfs may be compatible), and rebuild the 6.1.54 RT kernel against trixie.

### 1e. Files to modify
- `config` — RELEASE line
- `stage2/04-python/01-run.sh` — EXTERNALLY-MANAGED path, package list overhaul
- `stage2/05-pistomp/02-run.sh` — lilv block removal, mod-ui venv creation, libfluidsynth version
- `stage2/05-pistomp/03-run.sh` — RT kernel .deb swap
- `stage2/05-pistomp/01-run.sh` — check service paths (python3.13 paths)
- `stage2/*/00-packages` — remove trixie-dropped packages, add any new deps

### Verification
Run `./build-docker.sh` and confirm the image boots, JACK starts, mod-ui comes up, pi-stomp Python app launches.

---

## Part 2 — Critical Bug Fixes

These are blocking correctness issues. Some overlap with Part 1 and should be folded in simultaneously.

### 2a. jack2 — missing pi-controller-reset.patch
Without this patch, the PI controller integrator winds up unboundedly → failure rate ramps monotonically after jackd starts. This is the critical stability bug from pi-stomp#107.

**Fix:** Apply the patch when building jack2 from source (currently in `stage2/05-pistomp/02-run.sh`). The patch is in pistomp-arch's PKGBUILD — extract it and add to `stage2/05-pistomp/files/patches/jack2/pi-controller-reset.patch`. Add `git apply` call to the build block.

This is temporary — Part 3 moves this to a proper debpkg.

### 2b. pyliblo — Cython 3.x breakage
`pyliblo 0.10.0` fails to build with modern Cython. Switch to `pyliblo3` in `stage2/04-python/01-run.sh`. Already captured in Part 1b.

### 2c. mod-host — MIDI drain fix
Switch from upstream `mod-audio/mod-host` HEAD to `sastraxi/mod-host` branch `fix/effect-drain-midi`. Change the `git clone` URL and add `git checkout` in `stage2/05-pistomp/02-run.sh`.

### 2d. mod-ui fork
Currently using `TreeFallSound/mod-ui` HEAD. pistomp-arch uses `sastraxi/mod-ui` branch `more-fixes`. Evaluate whether to switch, or whether the TreeFallSound fork already incorporates those fixes.

### 2e. Files to modify
- `stage2/05-pistomp/02-run.sh` — jack2 patch apply, mod-host fork URL
- `stage2/05-pistomp/files/patches/jack2/pi-controller-reset.patch` — new file
- `stage2/04-python/01-run.sh` — pyliblo3

---

## Part 3 — Packaging Infrastructure (hybrid)

**Goal:** Stop building complex C components from source inside the image builder. Build them as arm64 .deb files in CI, publish to a TreeFallSound apt repo, consume via `apt install`.

### 3a. Structure
```
debpkgs/
  sfizz-pistomp/        ← already prototyped in example/dpkg/sfizz
    build.sh
    debian/
  jack2-pistomp/        ← new; replaces source build + patch
    build.sh
    debian/
  mod-host-pistomp/     ← new; replaces source build, includes MIDI drain fix
    build.sh
    debian/
```

**Complex components** (jack2, mod-host) live in TreeFallSound forks:
- `TreeFallSound/jack2` — upstream + `pi-controller-reset.patch` as a commit
- `TreeFallSound/mod-host` — fork of `sastraxi/mod-host` or upstream + MIDI drain patch

The `debian/` trees live under `debpkgs/` in **this** repo. The `build.sh` scripts clone the TreeFallSound fork and apply the packaging.

### 3b. CI workflow — build arm64 .debs
New workflow `.github/workflows/build-debs.yml`:
- Triggered on changes to `debpkgs/**` or manually
- Uses QEMU (`ubuntu-latest` + `qemu-user-static`) for arm64 cross-compilation
- Runs each `debpkgs/<pkg>/build.sh` inside an arm64 chroot
- Uploads `.deb` files as release assets

### 3c. Apt repository
- Use GitHub Pages + a simple `reprepro` or `aptly` layout to serve the apt repo
- `stage2/05-pistomp/02-run.sh` adds our apt source and installs via `apt install jack2-pistomp sfizz-pistomp mod-host-pistomp`

### 3d. Device update path
- Cache `.deb` files in `/var/cache/apt/archives/` in the image for offline rollback
- Devices can `apt update && apt upgrade` to get component updates without a full reflash

### 3e. Files to create/modify
- `debpkgs/jack2-pistomp/` — new (debian/ tree + build.sh)
- `debpkgs/mod-host-pistomp/` — new
- `debpkgs/sfizz-pistomp/` — merge from `example/dpkg/sfizz` branch
- `.github/workflows/build-debs.yml` — new CI workflow
- `stage2/05-pistomp/02-run.sh` — replace source builds with `apt install` calls

---

## Part 4 — Networking Fixes

10 changes from NETWORKING.md. All in `stage2/02-net-tweaks/` and related files.

### Changes
1. **wifi.powersave typo** — fix key name in `files/wifi-powersave.conf` (`wifi.powersaving` → `wifi.powersave`)
2. **Wired ethernet profile** — add NM connection file for direct ethernet with link-local fallback (169.254.x.x), `route-metric=200`
3. **MAC randomization disable** — add `[device] wifi.scan-rand-mac-address=no` to NM conf
4. **NM.conf** — replace `patch -i NetworkManager.conf.diff` approach with a direct file write in `03-run.sh` (drop the `.diff` file)
5. **WiFi check → systemd service** — replace the `rc.local` wifi credential check with a proper `pistomp-firstboot-wifi.service`
6. **Hotspot scripts** — rename to `pistomp-hotspot-*`, fix idempotency so re-running doesn't error
7. **Enable wifi-hotspot.service** — add symlink in `01-run.sh` (currently missing)
8. **Multihome routing dispatcher** — add NM dispatcher script for source-based routing when both eth+wifi are active (optional but recommended per NETWORKING.md)
9. **Sysctl multihome** — add `net.ipv4.conf.all.rp_filter=2` etc.
10. **WiFi credential firstboot** — wire into pistomp.conf flow (Part 5 dependency)

### Files to modify/create
- `stage2/02-net-tweaks/files/wifi-powersave.conf`
- `stage2/02-net-tweaks/files/ethernet-direct.nmconnection` — new
- `stage2/02-net-tweaks/01-run.sh` — install new connection profile, drop wpa_supplicant.conf
- `stage2/05-pistomp/03-run.sh` — replace NM.conf patch approach; drop `NetworkManager.conf.diff`
- `stage2/05-pistomp/files/services/pistomp-firstboot-wifi.service` — new

---

## Part 5 — UX Parity

Six features from UX-PARITY.md to reach pistomp-arch standard.

### 5a. LCD boot splash
- Add `lcd-splash` binary (pre-built arm64 .deb from pistomp-arch, or build from source)
- Add `pistomp-lcd-splash.service` that runs `lcd-splash` early in boot (before JACK starts)
- Add shutdown/reboot hooks to show message on LCD before poweroff

### 5b. Service readiness probes
- Add `wait-for-mod-host.sh` script that polls mod-host's socket before starting mod-ui
- This eliminates the mod-ui restart loop on slow boot
- Add as `ExecStartPre` in `mod-ui.service`

### 5c. MOD_HTML_DIR fix
- `mod-ui.service` currently points `MOD_HTML_DIR` to a nonexistent installed path
- Fix to point at the source tree location where mod-ui was cloned/installed

### 5d. pistomp.conf firstboot paradigm
- Add `pistomp.conf` template to the FAT32 boot partition (readable/editable on any OS)
- `firstboot.service` reads `pistomp.conf` and applies: WiFi SSID/password, hostname, user password
- Replaces the old RPi Imager 1.x flow (which set things via `userconf`/cmdline.txt tricks)
- Hooks into Part 4 item 10 for WiFi credential setup

### 5e. RT kernel baked in at build time
- Currently, the RT kernel install in `03-run.sh` may require a reboot to take effect
- Add `BOOTKERNEL=<version>` logic in `config_pistomp.txt` / `cmdline.txt` at build time so the device boots the RT kernel on first boot without needing a firstboot reboot

### 5f. Filesystem expansion — replace resize2fs_once
- `stage2/01-sys-tweaks/01-run.sh` installs a SysV init script (`resize2fs_once`) which is deprecated
- Replace with a systemd one-shot service + `growpart` (as described in UX-PARITY.md)
- Files: drop `files/resize2fs_once`, add `files/services/pistomp-expand-fs.service`

### Files to create/modify
- `stage2/05-pistomp/files/services/pistomp-lcd-splash.service` — new
- `stage2/05-pistomp/files/services/mod-ui.service` — MOD_HTML_DIR fix + ExecStartPre probe
- `stage2/05-pistomp/files/wait-for-mod-host.sh` — new
- `stage2/05-pistomp/files/pistomp.conf` — new template for boot partition
- `stage2/05-pistomp/files/firstboot.sh` — rewrite to use pistomp.conf
- `stage2/01-sys-tweaks/files/services/pistomp-expand-fs.service` — new
- `stage2/01-sys-tweaks/01-run.sh` — drop resize2fs_once, enable new service

---

## Recommended Order

1. **Part 2 bug fixes** (jack2 patch, pyliblo3, mod-host fork) — fold into Part 1 work
2. **Part 1 Trixie upgrade** — the foundation; everything else targets trixie
3. **Part 4 networking** — independent; can land in parallel with or just after Part 1
4. **Part 3 packaging infra** — once Trixie is stable; replaces source builds with .debs
5. **Part 5 UX parity** — can start after Part 1 lands; pistomp.conf depends on Part 4 item 10

## Open Questions to Resolve During Implementation

- **pystache**: Does pi-stomp still use it? If so, find a 3.13-compatible replacement (chevron, pystache fork).
- **RT kernel for trixie**: Source and rebuild process TBD — need to identify whether raspberrypi's trixie kernel tree has RT patches or if we need to cherry-pick them.
- **mod-ui fork divergence**: Confirm whether `TreeFallSound/mod-ui` HEAD already includes `sastraxi/mod-ui more-fixes` changes before deciding whether to switch.
- **lcd-splash binary**: Available as a pre-built .deb from pistomp-arch's CI, or needs to be added to the debpkgs/ CI here.
