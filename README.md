# pi-gen-pistomp

> **Not the official pi-Stomp distribution.** This is an independent community build of the OS image for [pi-Stomp v2/v3](https://github.com/TreeFallSound/pi-stomp) hardware, based on [pi-gen](https://github.com/RPI-Distro/pi-gen) (Raspberry Pi OS image builder). For the official installer, see [TreeFallSound/pi-gen-pistomp](https://github.com/TreeFallSound/pi-gen-pistomp).

Builds `deploy/pistompOS-<date>.img.xz` — a bootable Raspberry Pi OS image with the realtime kernel, JACK2 audio stack, and pi-Stomp application pre-installed.

## Quick start

### Prerequisites

- Docker
- ~20 GB free disk space

The build container runs native arm64 on Apple Silicon and arm64 Linux. On x86_64 Linux, `qemu-user-static` and `binfmt-support` must be installed — Docker handles the rest automatically.

### Step 1 — Build the RT kernel (once, ~20–40 min)

The PREEMPT_RT kernel `.deb` files are not in git. Build and cache them first:

```bash
./build-rt-kernel-docker.sh
```

This is a no-op if cached packages already exist in `cache/kernel/`. Re-run only when you want to update the kernel version.

### Step 2 — Build the OS image (~60–90 min)

```bash
./build-docker.sh -f && ./compress-img.sh
```

* `-f` removes any stale build container and clears `deploy/` before starting.
* [`build-docker.sh`](./build-docker.sh) leaves the uncompressed `.img` in `deploy/`;
* [`compress-img.sh`](./compress-img.sh) produces the dated `pistompOS-<date>.img.xz` you'll flash.

### Step 3 — Flash the image

Flash `deploy/pistompOS-<date>.img.xz` to a microSD card using the latest version of [Raspberry Pi Imager](https://www.raspberrypi.com/software/):

1. Open Raspberry Pi Imager.
2. **Choose OS** → **Use custom** → select the `pistompOS-<date>.img.xz` file.
3. **Choose storage** → select your microSD card.
4. Click **Write**.

### Step 4 — Configure `pistomp.conf` (before first boot)

After flashing, the card's boot partition mounts as a small FAT volume (named `boot` or `bootfs`). Open `pistomp.conf` on it and edit the values for your setup. The file lives at the root of the boot partition:

| Setting | Meaning | Default |
| :--- | :--- | :--- |
| `WIFI_SSID` | WiFi network name. Leave blank to skip WiFi. | `""` |
| `WIFI_PASSWORD` | WiFi password (WPA2/WPA3 personal). | `""` |
| `WIFI_COUNTRY` | ISO 3166-1 alpha-2 country code, e.g. `US`, `GB`, `DE`. Controls regulatory domain / allowed channels. | `"US"` |
| `HOSTNAME` | Device hostname on the network (appended with `.local`). | `"pistomp"` |
| `USER_PASSWORD` | Password for the `pistomp` user (used for SSH and console login). | `"pistomp"` |
| `TIMEZONE` | `tz` database timezone, e.g. `US/Central`, `Europe/London`, `America/Toronto`. | `"US/Central"` |
| `SSH_AUTHORIZED_KEY` | Paste your SSH public key here to enable key-based login. Leave blank to skip. | `""` |
| `JACK_SAMPLE_RATE` | JACK audio sample rate in Hz. netJACK mirrors this rate. | `"48000"` |
| `JACK_PERIOD` | JACK period (buffer frames). Lower = less latency, higher CPU cost. Powers-of-two typically: `64`, `128`, `256`. | `"64"` |

These settings are applied on first boot by `firstboot.sh` and then left in place for reference. To re-apply changed settings later, delete `/boot/firmware/firstboot.done` on the booted device and reboot.

### Step 5 — Install the card and boot

The microSD card slot on the pi-Stomp is on the **mainboard inside the enclosure** — you'll need to open the enclosure to access it. Insert the flashed card, close the enclosure, and power on.

**First boot takes up to a minute** to complete. During this time `firstboot.sh` writes your `pistomp.conf` settings to system files, expands the filesystem to fill the card, and initializes audio services. The LCD will update to let you know what it's working on, but keep in mind that the LCD will never turn off as long as there is power, so the display may be stale.

## Configuration sources (build-time)

| File | Purpose |
| :--- | :--- |
| `config` | pi-gen build settings: image name, Debian release, locale (not user config) |
| `config.sh` | All upstream URLs, branches, and version pins for custom packages (software sources) |
| `stage2/05-pistomp/files/pistomp.conf` | Template copied onto the image's boot partition — the runtime user config above |

To change which pi-stomp branch is baked in, edit `PISTOMP_BRANCH` in `config.sh`. All variables in `config.sh` are exported into the build environment and every `debian/rules` subprocess.

## Customization

- **WiFi, hostname, password, timezone, JACK settings**: edit `pistomp.conf` after flashing (above), or edit `stage2/05-pistomp/files/pistomp.conf` before building to change defaults
- **Packages added to the image**: `stage*/00-packages`
- **systemd services**: `stage2/05-pistomp/files/services/`
- **Networking**: `stage2/05-pistomp/files/` — see `NETWORKING.md` for design rationale
- **Boot splash**: `stage2/05-pistomp/files/splash.rgb565`

## Workflow for pi-stomp code changes

1. Push changes to `sastraxi/pi-stomp` on the `main` branch.
2. Run `./build-docker.sh -f && ./compress-img.sh` — Stage 3 clones the branch fresh at build time.

To use a different branch (or fork) during development, see [config.sh](./config.sh).

## Updating a package version

Package versions are owned by `debian/changelog` in each `debpkgs/<pkg>/` directory. To bump:

```bash
cd debpkgs/<pkg>
dch -v <new-version> "Description of change."
```

Then rebuild. [build.sh](./build.sh) reads the version from the changelog automatically — nothing else to update.

## OTA package updates

Custom `.deb` packages are also published to an apt repository hosted on GitHub Pages, so devices already running an image can pull updates without reflashing. The repository URL is pinned in [`config.sh`](./config.sh) (`APT_REPO_URL`) and written to `/etc/apt/sources.list.d/pistomp.list` on the image by `stage2/05-pistomp/05-run.sh`.

To push a package update over the air:

1. Bump the version in `debpkgs/<pkg>/debian/changelog` (see [Updating a package version](#updating-a-package-version)).
2. Push to `main`. The per-package workflow (`.github/workflows/build-<pkg>.yml`) builds the `.deb` and publishes a GitHub Release tagged `debpkg/<pkg>/<version>`.
3. The `publish-apt-repo` workflow rebuilds the `gh-pages` apt index from all release assets.
4. On the device, `pistomp-recovery`'s "Update packages" menu runs `apt-get update` and installs the new version. Or manually: `sudo apt-get update && sudo apt-get install --only-upgrade <pkg>`.

> Devices flashed from older images (before the OTA source was baked in) need the source added once: see `GUIDE.md` → *OTA updates*.

## Architecture

| Stage | What it builds |
| :--- | :--- |
| **0–1** | Base Debian Trixie system, bootloader |
| **2** | RT kernel, custom `.deb` packages, audio stack, networking, services |
| **3** | pi-stomp app, pedalboards, LV2 plugins, factory state |

Custom packages are built from source by `scripts/fetch-packages.sh` before the image build starts. Sources and URLs are pinned in `config.sh`. The built `.deb` files land in `cache/` alongside persistent uv, pip, and apt caches — all bind-mounted into the Docker build container at `/pistomp-cache` so subsequent builds skip re-downloading.

See **`GUIDE.md`** for full architecture detail, design decisions, debugging procedures, and kernel update instructions.

---

## Appendix — Advanced build commands

### Rebuild all custom packages from source

Custom `.deb` packages (`debpkgs/`) are cached in `cache/` and only rebuilt when missing. To force a full rebuild (e.g. after changing a `debian/control` dependency):

```bash
FORCE_REBUILD=1 ./build-docker.sh -f
```

(`FORCE_REBUILD` must be exactly `"1"` — the check is `!= "1"`, not a truthiness test.)

### Build a single package without a full image build

Iterate on one `debpkgs/<pkg>` without running the full image build:

```bash
./build-package-docker.sh jack2-pistomp
FORCE_REBUILD=1 ./build-package-docker.sh mod-ui
```

Mounts `cache/` at `/pistomp-cache` (same as the full build) and the repo root at `/pistomp` read-write (some packages write into `debpkgs/<pkg>/debian/` as a staging tree). The built `.deb` lands in `cache/` and is picked up by the next `./build-docker.sh` run without rebuilding.

### Resume an interrupted build

If the build container still exists from a previous run:

```bash
CONTINUE=1 ./build-docker.sh
```

### Keep the build container for inspection

```bash
PRESERVE_CONTAINER=1 ./build-docker.sh
docker exec -it pigen_work bash
```

### Useful environment variables

| Variable | Default | Effect |
| :--- | :--- | :--- |
| `CONTINUE` | `0` | Resume existing container instead of failing |
| `PRESERVE_CONTAINER` | `0` | Don't delete the container after build |
| `CONTAINER_NAME` | `pigen_work` | Override container name |
| `FORCE_REBUILD` | `0` | Set to `1` to rebuild all custom `.deb` packages from source, ignoring cache |

For kernel updates, debugging failed builds, mounting the built image, and apt-cacher troubleshooting, see **`GUIDE.md`**.
