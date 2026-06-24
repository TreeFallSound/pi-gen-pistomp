## Purpose

Builds the bootable OS image for pi-Stomp hardware.
Based on [pi-gen](https://github.com/RPI-Distro/pi-gen) (Debian/Raspberry Pi OS image builder).

## Ecosystem Context

Produces `pistompOS-<date>.img.xz` flashed to SD cards.
Integrates components:
1. **Base OS**: Raspberry Pi OS Lite (Debian Trixie / Python 3.13).
2. **Kernel**: Realtime (RT) kernel (64-bit ARM), installed from `.deb` at build time.
3. **Audio Engine**: JACK2 (with PI-controller reset fix), MOD-Host, MOD-UI (Stage 2).
4. **Application**: `pi-stomp` Python codebase, LV2 plugins, user data (Stage 3).

## Debugging build failures — start here

When something doesn't work at boot (service hangs, crash loops, missing files), the two highest-signal investigation steps are:

### 1. Read the build logs in `deploy/`

Every build writes a timestamped log to `deploy/build_log_*.log`. These contain the full stdout/stderr of every stage and substage — package installs, `dpkg` output, service file copies, kernel file placement, everything.

```bash
ls -t deploy/build_log_*.log | head -1   # latest build
```

Key things to grep for:
- `dpkg: error`, `dependency problems`, `unmet dependencies` — apt failures
- Package names that shouldn't be there (e.g. `libjack-jackd2-0` from upstream Debian shadowing a custom package)
- `failed`, `error`, `No such file` — stage script failures
- Service file copies (`cp`, `install`) — verify files landed in the right places

### 2. Mount the built image and look around

The uncompressed `.img` in `deploy/` is a full ext4 filesystem with a FAT boot partition. Mount it and inspect what actually ended up on disk:

```bash
# Find partition offsets (sector size is 512)
fdisk -l deploy/*pistompOS-*.img
# Typically: partition 1 (FAT boot) at sector 8192, partition 2 (ext4 root) at sector 1056768

# Mount root partition
sudo mkdir -p /mnt/pistomp-root
sudo mount -o loop,offset=$((1056768*512)) deploy/*pistompOS-*.img /mnt/pistomp-root

# Mount boot partition
sudo mkdir -p /mnt/pistomp-boot
sudo mount -o loop,offset=$((8192*512)) deploy/*pistompOS-*.img /mnt/pistomp-boot
```

Unmount when done:
```bash
sudo umount /mnt/pistomp-root /mnt/pistomp-boot
```

## Architecture

Build process executes ordered stages.

| Stage | Description | Key Contents |
| :--- | :--- | :--- |
| **0–1** | Bootstrap | Base Debian system, bootloader. |
| **2** | System/Audio | RT kernel, custom `.deb` packages (JACK2, MOD-Host, MOD-UI, etc.), networking, system tweaks. |
| **3** | Application | `pi-stomp` repo (via `.deb`), pedalboards, LV2 plugins, `factory-packages.list`. |

### Key stage2 substages

| Substage | Purpose |
| :--- | :--- |
| `01-sys-tweaks` | Packages, groups, SSH, filesystem expansion. |
| `02-net-tweaks` | WiFi country, rfkill defaults. |
| `03-set-timezone` | Timezone. |
| `04-python` | System pip packages (pyliblo3, netifaces2, JACK-Client, …). |
| `05-pistomp` | Custom `.deb` installs (JACK2, MOD-Host, MOD-UI, pi-stomp, pistomp-recovery), networking configs, RT kernel, services. |

### Notable design decisions

- **mod-ui runs in a Python 3.11 venv** (`/opt/pistomp/venvs/mod-ui`) because it requires `tornado==4.3`, which is incompatible with Python 3.13. All other pi-stomp code runs under the system Python 3.13. The venv is built in `debpkgs/mod-ui/debian/rules`.
- **JACK2 is built from source** as a `.deb` with the `pi-controller-reset.patch` applied (fixes PI integrator windup that causes monotonically increasing audio failures). The bundled `waf` is used with a patched waflib that replaces the removed `imp` module with `types`.
- **JACK configuration**: `jackdrc` is a script that sources `/etc/default/jack` and exits with an error if that file is missing. `firstboot.sh` writes `/etc/default/jack` from `pistomp.conf`. `jack.service` has `After=firstboot.service`, so JACK never starts before its configuration exists. `pistomp.conf` is the single source of truth for `JACK_SAMPLE_RATE` and `JACK_PERIOD`.
- **lilv is installed via apt** (`python3-lilv liblilv-dev`) — no source build needed on Trixie.
- **lcd-splash** is a C binary compiled from source in `debpkgs/lcd-splash/src/`. It uses `lgpio` (linked against the extracted `lg.deb` at build time) to drive the ILI9341 SPI LCD directly. The splash image is `stage2/05-pistomp/files/splash.rgb565`.
- **Realtime IRQ tuning** uses the `rtirq-init` apt package (not `rtirq` — the old name doesn't exist on Trixie). Config is installed to `/etc/default/rtirq`. A custom `rtirq.service` unit wraps the init script.
- **Networking** matches pistomp-arch exactly: wired NM profile with 15 s DHCP timeout + link-local fallback (`eth0`), wifi power-save off, MAC randomization off, multihome policy routing dispatcher.
- **WiFi hotspot** is started on demand by `wifi-check.service` (after NM settles), not via rc.local. It only starts if neither WiFi nor ethernet is connected.
- **WiFi roaming stability (wpa_supplicant 2.11 + `roamoff=1`)**. On a band/AP-steering mesh (e.g. Bell "Whole Home WiFi") the Debian image dropped WiFi repeatedly — disconnect/reconnect "roaming" — where pistomp-arch was rock-solid for months on the *same* hardware, firmware, mesh, and config. Root cause: **Debian Trixie ships `wpasupplicant` 2.10; arch shipped 2.11.** When the mesh steers the client to a BSSID advertising 802.11r, NetworkManager negotiates a WPA-PSK→FT-PSK *cross-AKM* roam; wpa_supplicant **2.10 fumbles that transition and tears the link down**, while **2.11 fixed it** ("improve cross-AKM roaming with driver-based SME/BSS selection"). This was confirmed empirically: the arch box runs wpa_supplicant 2.11 with FT *exposed* (`get_capability key_mgmt` lists `FT-PSK`) and firmware roaming *on* (`roamoff=0`), happily roaming a 5 GHz mesh node — so the differentiator is purely the supplicant version, not FT capability or config. Two independent mitigations are baked in: (1) **`wpa-supplicant-pistomp`** builds wpa_supplicant 2.11 from the upstream `hostap_2_11` tag as a `.deb` that `Provides/Replaces` the stock `wpasupplicant` (the real fix); (2) **`options brcmfmac roamoff=1`** (written by `firstboot.sh` to `/etc/modprobe.d/brcmfmac.conf`) disables in-driver roaming so a steer becomes a clean full reconnect — belt-and-suspenders, and harmless since this is a stationary floor appliance that never needs to roam. Refs: raspberrypi/linux#6265, Arch FS#63397, kernel BZ 206315.
- **QEMU**: not needed. The build runs in a native arm64 Docker container (Apple Silicon, arm64 Linux, arm64 CI). On x86_64 Linux, `dpkg-reconfigure qemu-user-binfmt` inside the container registers QEMU with the `F` flag — no QEMU binary needs to exist inside the rootfs.

## Hardware Targets

- **Architecture**: `arm64` (64-bit).
- **Devices**: Raspberry Pi 3, 4, 5, Zero 2 W.
- **Audio**: IQAudio DAC+.

## Building

### Prerequisites

- Docker
- ~20 GB free disk space
- On Linux x86_64: `qemu-user-static` and `binfmt-support` installed, binfmt_misc mounted.
- On Linux arm64 / macOS (Apple Silicon): no QEMU needed — the Docker container runs native arm64.

### Step 1 — Build the RT kernel (once, ~20–40 min)

The RT kernel `.deb` files are not checked into git. Build them first and they
are cached in `cache/kernel/` for all subsequent image builds.

```bash
./build-rt-kernel-docker.sh
```

Re-run only when you want to update the kernel version. The script skips the
build and exits immediately if cached packages already exist.

### Step 2 — Build the image

```bash
./build-docker.sh -f
```

The `-f`/`--force` flag removes any existing build container and clears `deploy/` automatically. Omit it if you want the default behaviour (abort when a stale container exists).

Output: `deploy/*pistompOS-*.img.xz` (run `./compress-img.sh` after `build-docker.sh` to produce it; `build-docker.sh` alone leaves the uncompressed `.img` in `deploy/`).

### Build a single package

Iterate on one `debpkgs/<pkg>` without running the full image build:

```bash
./build-package-docker.sh jack2-pistomp
FORCE_REBUILD=1 ./build-package-docker.sh mod-ui
```

Mounts `cache/` at `/pistomp-cache` (same as the full build) and the repo root at `/pistomp` read-write (some packages write into `debpkgs/<pkg>/debian/` as a staging tree). Sets `CACHE_DIR`, `WORKDIR`, `FORCE_REBUILD`, and all uv/pip cache vars automatically.

### Resume an interrupted build

If the build container still exists from a previous run:

```bash
CONTINUE=1 ./build-docker.sh
```

### Keep the container for inspection

```bash
PRESERVE_CONTAINER=1 ./build-docker.sh
# then: docker exec -it pigen_work bash
```

### Useful environment variables

| Variable | Default | Effect |
| :--- | :--- | :--- |
| `CONTINUE` | `0` | Resume existing container instead of failing |
| `PRESERVE_CONTAINER` | `0` | Don't delete the container after build |
| `CONTAINER_NAME` | `pigen_work` | Override container name |
| `FORCE_REBUILD` | `0` | Set to `1` to rebuild all custom `.deb` packages from source, ignoring cache. Must be exactly `"1"` — the check is `!= "1"`, not a truthiness test. |

## Configuration

### `config`
Build-time settings for the pi-gen image builder: image name, Debian release, compression, locale, keyboard layout, and the `pistomp` user account. Does **not** contain user-facing configuration — that is the old Raspberry Pi Imager 1.x pattern. WiFi, hostname, password, and timezone all live in `pistomp.conf` and are applied by `firstboot.sh` at first boot.

### `config.sh`
All upstream URLs, branches, and version pins for custom packages. `config.sh` uses `set -a`, so every variable is automatically exported into `build.sh`, `fetch-packages.sh`, and every `debian/rules` make subprocess. This makes `config.sh` the single source of truth for repository URLs and branches.

### `stage2/05-pistomp/files/pistomp.conf`
Runtime configuration copied to `/boot/pistomp.conf` on the image. Contains `JACK_SAMPLE_RATE` and `JACK_PERIOD`. `firstboot.sh` reads these and writes `/etc/default/jack`. To change the JACK buffer size, edit this file and rebuild.

## Package Management

Custom packages live under `debpkgs/<pkg>/`. Each has:
- `build.sh` — sets `PKG`/`VERSION`/`UPSTREAM_DIR`, sources `scripts/build-common.sh`, clones/downloads source, calls `dpkg-buildpackage` (or `dpkg-deb` for `lcd-splash` and `libfluidsynth2-compat`)
- `debian/` — standard Debian packaging directory; `debian/rules` uses exported config.sh vars for any fallback git clone

**`scripts/build-common.sh`** is sourced by every `build.sh` and provides:
- Env setup: `source config.sh`, `CACHE_DIR`, `WORKDIR`, `mkdir -p`
- `cache_check()` — exits 0 immediately if a versioned `.deb` already exists in `cache/` and `FORCE_REBUILD != 1`
- `move_to_cache [dir]` — moves `${PKG}_*.deb` from the build parent dir into `cache/`

**Version source of truth**: `debian/changelog`. To bump a package version:

```bash
cd debpkgs/<pkg>
dch -v <new-version> "Description of change."
```

`build.sh` reads the version from the changelog via `dpkg-parsechangelog` — no other files need updating.

Packages using `dpkg-deb --build` (`lcd-splash`, `libfluidsynth2-compat`) derive their version from `debian/control`'s `Version:` field instead.

**Stable symlinks**: `scripts/fetch-packages.sh` creates a `<pkg>.deb` symlink in `cache/` pointing to the latest versioned `.deb` (e.g. `mod-host-pistomp.deb → mod-host-pistomp_1.0.5-1_arm64.deb`). Stage scripts reference the unversioned symlink so version bumps don't require script edits. Dangling symlinks (versioned target deleted) are pruned automatically at the start of `fetch-packages.sh`.

### Package build order

`scripts/fetch-packages.sh` processes packages in dependency order (defined in the `PACKAGES` array). `lg` is built before `lcd-splash` because lcd-splash links against lgpio at compile time by extracting the lg `.deb` from cache.

### `cache/` directory structure

| Path | Contents |
| :--- | :--- |
| `cache/<pkg>_<ver>_arm64.deb` | Built/downloaded package archives |
| `cache/<pkg>.deb` | Stable symlink → latest versioned `.deb` |
| `cache/apt-repo/` | Generated local apt repo (rebuilt each run) |
| `cache/apt-cacher/` | apt-cacher-ng persistent cache (Debian packages) |
| `cache/uv-cache/` | uv wheel/sdist cache (`UV_CACHE_DIR`) |
| `cache/uv-python/` | uv-managed Python installs (`UV_PYTHON_INSTALL_DIR`) |
| `cache/pip-cache/` | pip download cache (`PIP_CACHE_DIR`) |

The uv and pip caches persist across builds automatically — `build-docker.sh` and `build-package-docker.sh` both set the relevant env vars to point here.

## Customization

- **Config**: Edit `config` (hostname, password, WiFi country, release).
- **Package pins/URLs**: Edit `config.sh`.
- **Packages added to image**: Edit `stage*/00-packages`.
- **Services**: Add/edit files in `stage2/05-pistomp/files/services/`.
- **JACK tuning**: Edit `JACK_SAMPLE_RATE` / `JACK_PERIOD` in `stage2/05-pistomp/files/pistomp.conf`.
- **Networking**: Files in `stage2/05-pistomp/files/` — see `NETWORKING.md` for design rationale.

## Kernel Updates

The RT kernel `.deb` files live in `cache/kernel/`. Updating requires:

1. Update `KERNEL_VERSION`, `KERNEL_LOCALVERSION`, and `LINUX_RPI_COMMIT` in `config.sh`.
2. Run `./build-rt-kernel-docker.sh` to build new `.deb` files.
3. Update `stage2/05-pistomp/03-run.sh` — the `dpkg -i` calls and the `cp`/`mv` block that moves kernel files into `/boot/firmware/`.
4. Rebuild the image.

> **Note**: Kernel `.deb` files must be built against the target Debian release (Trixie). Bookworm kernel `.deb` files will fail on Trixie's initramfs.

## Troubleshooting

### apt-cacher-ng crashes with "Could not reach APT_PROXY server"

The build uses `apt-cacher-ng` (container `pigen_apt_cacher`) as a Debian package proxy. If a previous build was interrupted mid-download, the cacher's on-disk cache can contain partial/corrupt files that cause it to exit immediately on restart.

Symptom in build output:
```
Could not reach APT_PROXY server: http://pigen_apt_cacher:3142
```

Check what's wrong:
```bash
docker logs pigen_apt_cacher
```

A corrupt entry looks like:
```
chmod: changing permissions of '/var/cache/apt-cacher-ng/_xstore/rsnap/...': No such file or directory
```

Fix — delete the corrupt subdirectory and remove the crashed container:
```bash
# find and remove the bad path printed in the docker logs
rm -rf cache/apt-cacher/_xstore/rsnap/debrep/dists/<whatever-was-corrupt>
docker rm -f pigen_apt_cacher
```

Then re-run the build normally. The cacher will restart clean and rebuild its index.

## Workflow for pi-stomp code changes

1. Push changes to `TreeFallSound/pi-stomp` `pistomp-v3` branch.
2. Stage 3 clones that branch at build time — no image changes needed.
3. Run `./build-docker.sh -f`.

To test a different branch, set `PISTOMP_BRANCH` in `config.sh`.
