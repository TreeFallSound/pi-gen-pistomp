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
| **2** | System/Audio | RT kernel, JACK2, MOD services, networking, system tweaks. |
| **3** | Application | `pi-stomp` repo, pedalboards, LV2 plugins, uv venv. |

### Key stage2 substages

| Substage | Purpose |
| :--- | :--- |
| `01-sys-tweaks` | Packages, groups, SSH, filesystem expansion. |
| `02-net-tweaks` | WiFi country, rfkill defaults. |
| `03-set-timezone` | Timezone. |
| `04-python` | System pip packages (pyliblo3, netifaces2, JACK-Client, …). |
| `05-pistomp` | JACK2, MOD-Host, MOD-UI venv, networking configs, RT kernel, services. |

### Notable design decisions

- **mod-ui runs in a Python 3.11 venv** (`/opt/mod-ui-venv`) because it requires `tornado==4.3`, which is incompatible with Python 3.13. All other pi-stomp code runs under the system Python 3.13.
- **JACK2 is built from source** with the `pi-controller-reset.patch` applied (fixes PI integrator windup that causes monotonically increasing audio failures). System `waf` is used instead of the bundled waflib (which uses the removed `imp` module).
- **lilv is installed via apt** (`python3-lilv liblilv-dev`) — no source build needed on Trixie.
- **Networking** matches pistomp-arch exactly: wired NM profile with 15 s DHCP timeout + link-local fallback (`eth0`), wifi power-save off, MAC randomization off, multihome policy routing dispatcher.
- **WiFi hotspot** is started on demand by `wifi-check.service` (after NM settles), not via rc.local. It only starts if neither WiFi nor ethernet is connected.

## Hardware Targets

- **Architecture**: `arm64` (64-bit).
- **Devices**: Raspberry Pi 3, 4, 5, Zero 2 W.
- **Audio**: IQAudio DAC+.

## Building

### Prerequisites

- Docker
- ~20 GB free disk space
- On Linux: `qemu-user-static` and `binfmt-support` installed, binfmt_misc mounted.
- On macOS: Docker Desktop (handles binfmt transparently via the Linux VM).

### Full build

```bash
# Remove any previous output and stale container
rm -rf deploy/*
docker rm -v pigen_work 2>/dev/null || true

./build-docker.sh
```

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

## Customization

- **Config**: Edit `config` (hostname, password, WiFi country, release).
- **Packages**: Edit `stage*/00-packages`.
- **Services**: Add/edit files in `stage2/05-pistomp/files/services/`.
- **Networking**: Files in `stage2/05-pistomp/files/` — see `NETWORKING.md` for design rationale.

## Kernel Updates

The RT kernel `.deb` files live in `stage2/05-pistomp/files/sys/`. Updating requires:

1. Place new `.deb` files in `files/sys/`.
2. Update `stage2/05-pistomp/03-run.sh` — the `dpkg -i` calls and the `cp`/`mv` block that moves kernel files into `/boot/firmware/<version>/`.
3. Rebuild.

> **Note**: Kernel `.deb` files must be built against the target Debian release (Trixie). Bookworm kernel `.deb` files will fail on Trixie's initramfs.

## Workflow for pi-stomp code changes

1. Push changes to `TreeFallSound/pi-stomp` `pistomp-v3` branch.
2. Stage 3 clones that branch at build time — no image changes needed.
3. Run `./build-docker.sh`.
