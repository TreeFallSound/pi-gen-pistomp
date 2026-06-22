# Debian package build vs. pistomp-arch (Arch Linux) — known differences

## Background

pi-gen-pistomp migrates the pi-Stomp OS from Arch Linux ARM (pistomp-arch) to
Debian (Raspberry Pi OS Trixie). The motivation is platform stability: Arch's
rolling-release baseline breaks unpredictably for an appliance. Debian/RasPiOS
provides a stable, well-tested upstream with official RPi integration.

**Guiding principle:** the Arch build is the *runtime reference* — what the
device should look like and how it should behave. Debian is the *delivery
vehicle*. When something in Arch is "better," the goal is to port it, not
leave it behind.

This document records confirmed differences. "Intentional" means we understand
the divergence and it is correct. "Possible gap" means it may need to be
ported. "Road-mapped" means we know how to close the gap but haven't done it
yet.

## Fundamental build model difference

In Arch, the build chroot *is* the target system. All scripts run inside the
filesystem that becomes the final image via `arch-chroot`, so anything
installed during the build is automatically present at runtime.

In Debian there are three separate environments:

1. **Docker container** — the build host (native aarch64; no QEMU tax on
   Apple Silicon or aarch64 Linux). Tools installed here (e.g. `uv`, compiler
   toolchain) are available for building `.deb` packages but never reach the Pi.
2. **`.deb` build chroot** — a temporary environment `dpkg-buildpackage` uses
   to compile each package. Declared in `Build-Depends`; torn down after build.
3. **`ROOTFS_DIR`** — the target filesystem, built by pi-gen via debootstrap.
   Only things explicitly installed here (via `on_chroot`, `.deb` installs, or
   `install` calls in run scripts) reach the Pi.

This separation is why `uv` can't be declared in `Build-Depends` (that only
populates the `.deb` build chroot) and why a dedicated stage2 run script
(`05-run.sh`) is needed to install it into the target image.

---

## Build architecture

| | Debian (pi-gen-pistomp) | Arch (pistomp-arch) |
|---|---|---|
| Base system | Raspberry Pi OS Trixie (debootstrap via pi-gen) | Arch Linux ARM (pacstrap) |
| Build flow | pi-gen stages 0–2 inside Docker | 10 sequential `run_in_chroot` scripts |
| Kernel compilation | Native aarch64 (no QEMU on Apple Silicon / aarch64 Linux) | Native aarch64 inside chroot |
| Package format | `.deb` (dpkg/apt) | `.pkg.tar.zst` (pacman) |
| Custom packages | 17 `.deb` packages | 18 `.pkg.tar.zst` packages |
| Final compression | xz (configurable: zip/gz/xz/none) | zstd -T0 -3 |

The two-phase approach is the same in both repos: build the RT kernel once
(cached), then build the OS image consuming it.

---

## uv availability

| | Arch | Debian |
|---|---|---|
| Install method | Official curl script during 04-native-pkgs.sh | Same curl script in Dockerfile (build host) and 05-run.sh (target) |
| Install location on device | `/opt/pistomp/bin/uv` | `/opt/pistomp/bin/uv` (stage2/05-pistomp/05-run.sh) |
| On target device | **Yes** | **Yes** — via curl script in 05-run.sh |
| PATH | Not modified by installer; scripts use full path | `/opt/pistomp/bin` added via `/etc/profile.d/pistomp.sh` |

Both use `INSTALLER_NO_MODIFY_PATH=1`. Debian adds `/opt/pistomp/bin` to PATH
system-wide via `profile.d` so `uv` is available interactively and to any
process that inherits a login environment. Systemd service units that need uv
at runtime should add `Environment=PATH=/opt/pistomp/bin:...` explicitly.

`uv` cannot be declared in Debian `Build-Depends` or `Depends` because it is
not a Debian package — the build-time copy lives only in the Docker image.

---

## Package coverage

| Package | Debian | Arch | Notes |
|---|---|---|---|
| jack2-pistomp | ✓ | ✓ | See below |
| mod-host-pistomp | ✓ | ✓ | |
| mod-ui | ✓ | ✓ | See below |
| pi-stomp | ✓ | ✓ | |
| pistomp-recovery | ✓ | ✓ | |
| lg (lgpio) | ✓ | ✓ | See below |
| lcd-splash | ✓ | ✓ | |
| hylia | ✓ | ✓ | |
| sfizz-pistomp | ✓ | ✓ | |
| fluidsynth-headless | ✓ | ✓ | |
| libfluidsynth2-compat | ✓ | ✓ | |
| amidithru | ✓ | ✓ | |
| mod-midi-merger | ✓ | ✓ | |
| mod-ttymidi | ✓ | ✓ | |
| jack-capture | ✓ | ✓ | See below |
| browsepy | ✓ deb | venv in 05-python.sh | Debian packages it; Arch builds a lightweight venv |
| touchosc2midi | ✓ deb | venv in 05-python.sh | Same |
| jackbridge | ✓ deb | — | Not found in Arch; may be omitted |
| pistomp-python311 | — | ✓ | Arch ships a standalone Python 3.11 package; Debian embeds it in the mod-ui venv |

---

## jack2-pistomp

### waf invocation

Both builds apply the same two patches (`jack2-1.9.22-db-5.3.patch`,
`pi-controller-reset.patch`) and solve the same problem: the bundled waflib
uses the `imp` module removed in Python 3.12.

| | Arch | Debian |
|---|---|---|
| waflib source | System `waf` (bundled waflib deleted in `prepare()`) | Bundled `./waf` + `waflib-imp-to-types.patch` |
| Invocation | `waf configure && waf build` | `./waf configure && ./waf build` |
| PYTHONPATH | `export PYTHONPATH="${PWD}:${PYTHONPATH:-}"` (both build and install) | Not set — `./waf` finds its own tools |

The PYTHONPATH export in Arch is a consequence of using system waf (which
needs to locate jack2's waf tool modules via the Python path). With the
bundled `./waf`, this is handled internally and PYTHONPATH is not needed.

### Debian-only patches

- `systemd-pkgconfig.patch` — fixes systemd.pc detection on Debian Trixie
- `systemd-unit-dir.patch` — provides a fallback unit dir when pkg-config returns nothing

These are not needed on Arch because Arch's systemd packaging exposes
pkg-config differently.

---

## jack-capture

| | Arch | Debian |
|---|---|---|
| Base | `v0.9.73` tag | Post-0.9.73 master commit pinned via `JACK_CAPTURE_REF` |
| Post-release fixes | Applied via `jack_capture-post-release-fixes.patch` (29 commits) | Already included in the pinned commit — no patch needed |

---

## mod-ui — Python 3.11 isolation

Both builds use Python 3.11 for mod-ui (required by `tornado==4.3`, which is
incompatible with Python 3.13).

| | Arch | Debian |
|---|---|---|
| Python 3.11 source | Separate `pistomp-python311` package at `/opt/pistomp/python311/` | `uv python install 3.11` into uv's build cache |
| Venv creation | `uv venv --python /opt/pistomp/python311/bin/python3.11 --relocatable` | `uv python find 3.11 \| xargs python -m venv --copies` |
| Runtime dependency | `pistomp-python311` package must be installed | Python 3.11 binary is copied into the venv; no external dep |
| Dependency locking | `uv sync --frozen` against `uv.lock` | `pip install tornado==4.3` + `pip install <src>` (unlocked) |

**Road-mapped:** mod-ui's Debian build does not yet use a `uv.lock`. The path
to fix this:
1. Add `pyproject.toml` to the `TreeFallSound/mod-ui` fork declaring
   `tornado==4.3` and other direct deps, with `requires-python = ">=3.11,<3.12"`.
2. Run `uv lock` in that repo to generate `uv.lock`.
3. Change `debpkgs/mod-ui/debian/rules` to use `uv sync --frozen --no-dev
   --no-editable --project "$(MODUI_SRC_DIR)"` — identical pattern to pi-stomp.

This work lives in the mod-ui fork repo; the deb build rules just consume the
lock file.

---

## lg (lgpio) — Python module installation

Arch uses `setup.py install --root=...` (discovers site-packages at package
time). The Debian build installs the two files manually to avoid
`dh_usrlocal` rejecting files under `/usr/local/` and to sidestep the
`setup.py install` deprecation warning:

```
/usr/lib/python3/dist-packages/lgpio.py
/usr/lib/python3/dist-packages/_lgpio.so
```

---

## pi-stomp / pistomp-recovery — venv strategy

Both packages use `--system-site-packages` against `/usr/bin/python3` (system
Python 3.13). Because `/usr/bin/python3` exists on the target device,
`--copies` is not needed — the venv symlink is valid at runtime.

Arch uses `--relocatable`; Debian uses plain `uv venv` (relocation is not
required when the interpreter path is stable across build and target).

`uv sync` is called with `--no-editable` in both repos so the project wheel
lands in `site-packages` rather than as an editable `.pth` pointing to the
build tree. Both consume a pinned `uv.lock` from the source repo (`--frozen`).

---

## Python environment overview

| Component | Debian | Arch |
|---|---|---|
| System Python | 3.13 (`/usr/bin/python3`) | 3.13 (`/usr/bin/python`) |
| mod-ui | Python 3.11 copied into venv (via `--copies`) | Python 3.11 via `pistomp-python311` package |
| pi-stomp | System Python 3.13 venv + `--system-site-packages` | Same |
| pistomp-recovery | System Python 3.13 venv + `--system-site-packages` | Same |
| browsepy | `.deb` with venv | Venv created in 05-python.sh |
| touchosc2midi | `.deb` with venv | Venv created in 05-python.sh |
| System-wide pip installs | Yes — stage2/04-python installs ~10 packages globally via pip3 | No — all packages isolated to venvs |

**Possible gap:** Debian's `stage2/04-python` removes the `EXTERNALLY-MANAGED`
marker and installs packages (pyserial, pycryptodomex, aggdraw, flask,
netifaces2, mido, docopt, pyliblo3, etc.) globally via `pip3`. Arch isolates
everything to venvs. The global installs are fragile (silently updated,
invisible to package management). Packages already declared in component
`pyproject.toml` files should be removed here; the remainder need to be
traced to their consumer and moved to the appropriate venv.

---

## systemd service enablement

Both repos use manual `ln -sf` symlinks into `wants/` directories rather than
`systemctl enable` or `deb-systemd-helper`. Debian's deb rules override
`dh_installsystemd` to prevent it from running.

### Service list differences

| Service | Debian | Arch |
|---|---|---|
| rtirq | ✓ | — |
| mod-midi-merger-broadcaster | — | ✓ |
| wifi-check / wifi-hotspot | wifi-check.service | wifi-hotspot.service |

### mod-ala-pi-stomp.service

Ported from Arch. Both now use:

```
Requires=jack.service mod-host.service mod-ui.service
After=jack.service mod-host.service mod-ui.service
Restart=on-failure
RestartSec=5
LimitRTPRIO=70
```

Previously Debian used `Requires=mod-ui.service` only (boot race risk),
`Restart=always`, `RestartSec=2`, `LimitRTPRIO=64`.

---

## Networking

Both match on: NM keyfile plugin, dnsmasq, wifi power-save off, MAC
randomization off, wired DHCP → link-local fallback, multihome policy-routing
dispatcher.

One confirmed difference: wired NM profile uses **`eth0`** here and **`end0`**
in Arch. Modern kernels with predictable interface naming use `end0`; older or
RPi-specific udev rules may use `eth0`. Check which name the target kernel
exposes before changing either.

---

## Kernel

| | Debian | Arch |
|---|---|---|
| Source | Raspberry Pi Linux (pinned commit in config.sh) | Arch ARM linux-rpi PKGBUILD base (pinned commit) |
| diffconfig | ~99 lines (RT + size optimisations, disables XFS/BTRFS/GPU debug) | ~400 lines (Arch ARM baseline + RT additions) |
| Build method | Cross-compile x86_64 → arm64 (`bindeb-pkg`) | Native aarch64 (`makepkg`) |
| Output | `.deb` files in `stage2/05-pistomp/files/sys/` | `.pkg.tar.*` files in `cache/` |
| Arch extra patches | — | `disable-heavy-features.patch`, `0001-Make-proc-cpuinfo-consistent-on-arm64-and-arm.patch` |

---

## Cleanup

| | Debian | Arch |
|---|---|---|
| Build toolchain | Kept (part of base OS) | Removed (`base-devel`, gcc, kernel headers) |
| Kernel module pruning | Minimal | Explicit — removes GPU/network/staging drivers |
| Firmware pruning | Minimal | Keeps only brcm/cypress (RPi WiFi/BT) |
| Python/uv cache | Basic | Removes uv download cache explicitly |
| SBOM | syft generates SBOM on export | Not generated |

---

## Possible gaps (to investigate)

- **uv in systemd units** — `/etc/profile.d/pistomp.sh` only affects login
  shells. Service units that invoke uv directly need
  `Environment=PATH=/opt/pistomp/bin:...` in the unit file.
- **Global pip3 installs** — see Python environment section above.
- **jackbridge** — present as a `.deb` here but not found in pistomp-arch;
  unclear if it is needed at runtime.
- **Audio limits** — Debian installs `/etc/security/limits.d/99-audio.conf`
  and a udev rule for CPU DMA latency (`99-cpu-dma-latency.rules`). Arch
  relies on `LimitRTPRIO=70` in the service unit. Verify whether the limits
  file is still needed alongside the unit directive.
- **eth0 vs end0** — see Networking section above.
- **mod-midi-merger-broadcaster** — enabled in Arch, not in Debian. Needed?
