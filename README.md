# pi-gen-pistomp

Builds the bootable OS image for [pi-Stomp](https://github.com/TreeFallSound/pi-stomp) hardware. Based on [pi-gen](https://github.com/RPI-Distro/pi-gen) (Raspberry Pi OS image builder).

Produces `deploy/pistompOS-<date>.img.xz` — flash to SD card and boot.

## Prerequisites

- Docker
- ~20 GB free disk space

The build container runs native arm64 on Apple Silicon and arm64 Linux. On x86_64 Linux, `qemu-user-static` and `binfmt-support` must be installed — Docker handles the rest automatically.

## Build

### Step 1 — RT kernel (once, ~20–40 min)

The PREEMPT_RT kernel `.deb` files are not in git. Build and cache them first:

```bash
./build-rt-kernel-docker.sh
```

This is a no-op if cached packages already exist in `cache/kernel/`.

### Step 2 — OS image (~60–90 min)

```bash
./build-docker.sh -f
```

`-f` removes any stale build container and clears `deploy/` before starting. `build-docker.sh` leaves the uncompressed `.img` in `deploy/`; run `./compress-img.sh` to produce the dated `.img.xz`.

### Rebuild all custom packages from source

Custom `.deb` packages (`debpkgs/`) are cached in `cache/` and only rebuilt when missing. To force a full rebuild (e.g. after changing a `debian/control` dependency):

```bash
FORCE_REBUILD=1 ./build-docker.sh -f
```

To rebuild a single package without a full image build, use `build-package-docker.sh`:

```bash
./build-package-docker.sh jack2-pistomp
FORCE_REBUILD=1 ./build-package-docker.sh mod-ui
```

This drops you into the same Docker environment as the full build, with `cache/` mounted at `/pistomp-cache`. The built `.deb` lands in `cache/` and will be picked up by the next `./build-docker.sh` run without rebuilding.

### Resume an interrupted build

```bash
CONTINUE=1 ./build-docker.sh
```

### Inspect a failed build

```bash
PRESERVE_CONTAINER=1 ./build-docker.sh
docker exec -it pigen_work bash
```

## Configuration

| File | Purpose |
| :--- | :--- |
| `config` | pi-gen build settings: image name, Debian release, locale (not user config) |
| `config.sh` | All upstream URLs, branches, and version pins for custom packages |

To change what pi-stomp branch is baked in, edit `PISTOMP_BRANCH` in `config.sh`. All variables in `config.sh` are automatically exported into the build environment and into every `debian/rules` make subprocess.

## Updating a package version

Package versions are owned by `debian/changelog` in each `debpkgs/<pkg>/` directory. To bump:

```bash
cd debpkgs/<pkg>
dch -v <new-version> "Description of change."
```

Then rebuild. `build.sh` reads the version from the changelog automatically — nothing else to update.

## Customization

- **WiFi, hostname, password, timezone**: edit `stage2/05-pistomp/files/pistomp.conf` before building, or edit the copy on the boot partition after flashing — `firstboot.sh` applies it on first boot
- **JACK buffer size / sample rate**: `JACK_PERIOD` / `JACK_SAMPLE_RATE` in `pistomp.conf`
- **Packages added to the image**: `stage*/00-packages`
- **systemd services**: `stage2/05-pistomp/files/services/`
- **Networking**: `stage2/05-pistomp/files/` — see `NETWORKING.md`
- **Boot splash**: `stage2/05-pistomp/files/splash.rgb565`

## Architecture

| Stage | What it builds |
| :--- | :--- |
| **0–1** | Base Debian Trixie system, bootloader |
| **2** | RT kernel, custom `.deb` packages, audio stack, networking, services |
| **3** | pi-stomp app, pedalboards, LV2 plugins, factory state |

Custom packages are built from source by `scripts/fetch-packages.sh` before the image build starts. Sources and URLs are pinned in `config.sh`. The built `.deb` files land in `cache/` alongside persistent uv, pip, and apt caches — all bind-mounted into the Docker build container at `/pistomp-cache` so subsequent builds skip re-downloading.

See `GUIDE.md` for architecture detail, design decisions, and kernel update instructions.

## Workflow for pi-stomp code changes

1. Push changes to `TreeFallSound/pi-stomp` on the `pistomp-v3` branch.
2. Run `./build-docker.sh -f && ./compress-img.sh` — Stage 3 clones the branch fresh at build time.

To use a different branch during development, set `PISTOMP_BRANCH` in `config.sh`.
