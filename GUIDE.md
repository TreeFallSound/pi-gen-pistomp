## Purpose

Builds the bootable OS image for pi-Stomp hardware.
Based on [pi-gen](https://github.com/RPI-Distro/pi-gen) (Debian/Raspberry Pi OS image builder).

## Ecosystem Context

Produces `pistompOS-lite.img.xz` flashed to SD cards.
Integrates components:
1. **Base OS**: Raspberry Pi OS Lite (Debian Trixie / Python 3.13).
2. **Kernel**: Realtime (RT) kernel (64-bit ARM), installed from `.deb` at build time.
3. **Audio Engine**: JACK2 (with PI-controller reset fix), MOD-Host, MOD-UI (Stage 2).
4. **Application**: `pi-stomp` Python codebase, LV2 plugins, user data (Stage 3).

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
are cached in `stage2/05-pistomp/files/sys/` for all subsequent image builds.

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

Output: `deploy/*pistompOS-lite.img.xz`

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

## Configuration

### `config`
Build-time settings for the pi-gen image builder: image name, Debian release, compression, locale, keyboard layout, and the `pistomp` user account. Does **not** contain user-facing configuration — that is the old Raspberry Pi Imager 1.x pattern. WiFi, hostname, password, and timezone all live in `pistomp.conf` and are applied by `firstboot.sh` at first boot.

### `config.sh`
All upstream URLs, branches, and version pins for custom packages. `config.sh` uses `set -a`, so every variable is automatically exported into `build.sh`, `fetch-packages.sh`, and every `debian/rules` make subprocess. This makes `config.sh` the single source of truth for repository URLs and branches.

### `stage2/05-pistomp/files/pistomp.conf`
Runtime configuration copied to `/boot/pistomp.conf` on the image. Contains `JACK_SAMPLE_RATE` and `JACK_PERIOD`. `firstboot.sh` reads these and writes `/etc/default/jack`. To change the JACK buffer size, edit this file and rebuild.

## Package Management

Custom packages live under `debpkgs/<pkg>/`. Each has:
- `build.sh` — sources `config.sh`, derives `VERSION` from `debian/changelog`, clones source, calls `dpkg-buildpackage`
- `debian/` — standard Debian packaging directory; `debian/rules` uses exported config.sh vars for any fallback git clone

**Version source of truth**: `debian/changelog`. To bump a package version:

```bash
cd debpkgs/<pkg>
dch -v <new-version> "Description of change."
```

`build.sh` reads the version from the changelog via `dpkg-parsechangelog` — no other files need updating.

Packages using `dpkg-deb --build` instead of `dpkg-buildpackage` (currently `lcd-splash` and `libfluidsynth2-compat`) derive their version from `debian/control`'s `Version:` field.

### Package build order

`scripts/fetch-packages.sh` processes packages in dependency order (defined in the `PACKAGES` array). `lg` is built before `lcd-splash` because lcd-splash links against lgpio at compile time by extracting the lg `.deb` from cache.

## Customization

- **Config**: Edit `config` (hostname, password, WiFi country, release).
- **Package pins/URLs**: Edit `config.sh`.
- **Packages added to image**: Edit `stage*/00-packages`.
- **Services**: Add/edit files in `stage2/05-pistomp/files/services/`.
- **JACK tuning**: Edit `JACK_SAMPLE_RATE` / `JACK_PERIOD` in `stage2/05-pistomp/files/pistomp.conf`.
- **Networking**: Files in `stage2/05-pistomp/files/` — see `NETWORKING.md` for design rationale.

## Kernel Updates

The RT kernel `.deb` files live in `stage2/05-pistomp/files/sys/`. Updating requires:

1. Update `KERNEL_VERSION`, `KERNEL_LOCALVERSION`, and `LINUX_RPI_COMMIT` in `config.sh`.
2. Run `./build-rt-kernel-docker.sh` to build new `.deb` files.
3. Update `stage2/05-pistomp/03-run.sh` — the `dpkg -i` calls and the `cp`/`mv` block that moves kernel files into `/boot/firmware/<version>/`.
4. Rebuild the image.

> **Note**: Kernel `.deb` files must be built against the target Debian release (Trixie). Bookworm kernel `.deb` files will fail on Trixie's initramfs.

## Workflow for pi-stomp code changes

1. Push changes to `TreeFallSound/pi-stomp` `pistomp-v3` branch.
2. Stage 3 clones that branch at build time — no image changes needed.
3. Run `./build-docker.sh -f`.

To test a different branch, set `PISTOMP_BRANCH` in `config.sh`.
