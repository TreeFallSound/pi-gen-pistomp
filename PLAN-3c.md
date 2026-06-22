# PLAN-3c: Custom .deb Packages for Stage 2

Detailed specs for the ten packages that need custom `.deb` files.
Each lives under `debpkgs/<pkg-name>/` with a `build.sh` + `debian/` tree following
the PLAN-3a contract.

---

## 1. jack2-pistomp

- **Source**: `https://github.com/jackaudio/jack2.git` tag `v1.9.22` (`$JACK2_REPO` / `$JACK2_TAG`)
- **Patches** (both go in `debian/patches/`):
  - `pi-controller-reset.patch` — copy from `stage2/05-pistomp/files/patches/pi-controller-reset.patch`
  - `jack2-1.9.22-db-5.3.patch` — copy from `pkgbuilds/jack2-pistomp/jack2-1.9.22-db-5.3.patch` (links against libdb 5.3; Trixie ships `libdb5.3-dev`)
- **Build flags**: system waf (`pip3 install waf` in CI runner's build-deps step); `rm -rf waflib` before configure so bundled waflib (uses removed `imp` module) is not used. Waf configure flags: `--prefix=/usr --autostart=none --systemd-unit --classic --dbus`. CXXFLAGS must include `-I/usr/include/db5.3`; LDFLAGS must include `-ldb-5.3`.
- **debian/rules**: use `dh $@ --buildsystem=waf` or override `dh_auto_configure` / `dh_auto_build` / `dh_auto_install` to call `waf configure`, `waf build`, `waf --destdir=$(CURDIR)/debian/jack2-pistomp install`
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), python3, waf | python3-waf, libasound2-dev, libdb5.3-dev, libdbus-1-dev, libsamplerate0-dev, libopus-dev, pkg-config, quilt`
  - Depends: `${shlibs:Depends}, ${misc:Depends}, libasound2, libdb5.3, libdbus-1-3, libsamplerate0, libopus0`
  - Provides: `jackd2, libjack-dev`
  - Conflicts/Replaces: `jackd2, jack2`
- **Issues**: `dh --buildsystem=waf` requires `dh-python` or manual overrides — prefer explicit `override_dh_auto_*` rules calling waf directly. Quilt must apply db5.3 patch before waflib removal.

---

## 2. mod-host-pistomp

- **Source**: `$MOD_HOST_REPO` branch `$MOD_HOST_BRANCH` (`https://github.com/sastraxi/mod-host.git` / `fix/effect-drain-midi`). No stable tag — `build.sh` clones with `--branch "${MOD_HOST_BRANCH}"`.
- **Version string**: parse from `Makefile` or pin as `0.10.6` in `debian/changelog`. Cache check uses `mod-host-pistomp_0.10.6*_arm64.deb`.
- **Build**: plain `make` / `make install PREFIX=/usr`. No cmake, no autoconf.
- **Build-time dep on hylia**: `libjack-dev` provides the JACK headers; Hylia installs `libhylia.so` and headers to `/usr`. In CI the runner must have hylia's `.deb` installed before building mod-host-pistomp. Add `hylia (>= 1.0)` to Build-Depends; order the CI step to install `cache/hylia_*.deb` first.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), libjack-jackd2-dev | libjack-dev, liblilv-dev, libfftw3-dev, liblo-dev, libreadline-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}, liblilv0, libfftw3-single3, liblo7, libreadline8`
  - Provides: `mod-host`
  - Conflicts/Replaces: `mod-host`
- **Issues**: branch (not tag) means `FORCE_REBUILD` should be set on every CI run for this package, or cache key includes the branch HEAD commit SHA.

---

## 3. hylia

- **Source**: `$HYLIA_REPO` (`https://github.com/falkTX/Hylia.git`), no stable tag — clone master. Set version as `1.0` in `debian/changelog`.
- **Build**: `make PREFIX=/usr NOOPT=true` then `make PREFIX=/usr DESTDIR=... install`. `NOOPT=true` avoids architecture-specific optimisation flags that break cross or emulated builds.
- **Installs**: `libhylia.so` + headers to `/usr/lib` and `/usr/include`. The `.deb` must also ship the headers so mod-host-pistomp can Build-Depend on it.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13)`
  - Depends: `${shlibs:Depends}, ${misc:Depends}`
  - No Conflicts/Replaces (no upstream Debian package)
- **Issues**: upstream Makefile installs to `PREFIX/lib` not `PREFIX/lib/aarch64-linux-gnu`; `lintian` may warn but this is acceptable for our private repo.

---

## 4. amidithru

- **Source**: `$AMIDITHRU_REPO` (`https://github.com/BlokasLabs/amidithru.git`), master branch, version `1.0`.
- **Build**: plain `make`. Install: `install -Dm755 amidithru /usr/bin/amidithru`.
- **Patch**: current `02-run.sh` does `sed -i 's/CXX=g++.*/CXX=g++/' Makefile` to strip hardcoded compiler flags. This becomes `debian/patches/fix-cxx-flags.patch` (quilt). One-liner patch, series file required.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), libasound2-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}, libasound2`
- **debian/rules**: `dh $@` with override `dh_auto_build` calling `make` and override `dh_auto_install` calling `install -Dm755 amidithru $(CURDIR)/debian/amidithru/usr/bin/amidithru`.

---

## 5. mod-midi-merger

- **Source**: `$MOD_MIDI_MERGER_REPO` (`https://github.com/mod-audio/mod-midi-merger`), master, version `1.0`.
- **Build**: cmake with `-DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_POLICY_VERSION_MINIMUM=3.5`. Note: pistomp-arch uses `micahvdm/mod-midi-merger` fork — verify which repo is canonical. `config.sh` currently points to `mod-audio/mod-midi-merger`; keep that.
- **Patch**: current `02-run.sh` does `sed -i 's/^[[:space:]]*set(CMAKE_INSTALL_PREFIX[[:space:]]*\/usr)/# &/' CMakeLists.txt` to un-hard-code `/usr`. This becomes `debian/patches/fix-install-prefix.patch`. The `cmake -DCMAKE_INSTALL_PREFIX=/usr` flag from `dh_auto_configure` then sets the correct prefix.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), cmake, libjack-jackd2-dev | libjack-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}`
- **debian/rules**: `dh $@ --buildsystem=cmake` with `override_dh_auto_configure` passing `-DCMAKE_POLICY_VERSION_MINIMUM=3.5` alongside the default flags.

---

## 6. mod-ttymidi

- **Source**: `$MOD_TTYMIDI_REPO` (`https://github.com/moddevices/mod-ttymidi.git`), master, version `1.0`.
- **Build**: plain `make`. Upstream Makefile installs binary as `ttymidi` to `$(PREFIX)/bin`.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), libjack-jackd2-dev | libjack-dev, libasound2-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}`
- **debian/rules**: override `dh_auto_install` to call `make PREFIX=/usr DESTDIR=$(CURDIR)/debian/mod-ttymidi install`.
- **Issues**: upstream binary is named `ttymidi` not `mod-ttymidi`; the `.deb` installs it to `/usr/bin/ttymidi`. Service files reference that name — no rename needed.

---

## 7. sfizz-pistomp

- **Source**: `https://github.com/sfztools/sfizz-ui.git` tag `1.2.3`, recurse submodules (library sub-repo required).
- **Adapt from prototype** (`example/dpkg/sfizz` branch): the `debian/` tree (control, rules) is correct. Fix two known issues:
  1. **Hardcoded `dpkg -i` line in `build.sh`**: replace with the PLAN-3a pattern — move output `.deb` to `$CACHE_DIR`, no install. The prototype `build.sh` still has `dpkg -i "${PKG}_${VERSION}-7_arm64.deb"` — remove this entirely.
  2. **No cache output step**: add the `find ... -exec mv {} "${CACHE_DIR}/" \;` block from the PLAN-3a template after the build.
- **Patch**: `add-mod-filetype.patch` from `pkgbuilds/sfizz-pistomp/add-mod-filetype.patch` — copy to `debian/patches/` and add to `debian/patches/series`.
- **debian/control** (keep from prototype, add Conflicts):
  - Build-Depends: `debhelper-compat (= 13), cmake, git, lv2-dev, libsndfile1-dev, libsamplerate0-dev`
  - Provides: `sfizz, sfizz-lv2`; Conflicts/Replaces: `sfizz, sfizz-lv2`
- **config.sh addition**: add `SFIZZ_TAG="1.2.3"` and `SFIZZ_REPO="https://github.com/sfztools/sfizz-ui.git"`.
- **Build note**: limit parallelism to avoid OOM (`-j$(PARALLEL_JOBS)` in `override_dh_auto_build`; the prototype's rules file already does this correctly).

---

## 8. fluidsynth-headless

- **Source**: `https://github.com/FluidSynth/fluidsynth/archive/v2.5.2.tar.gz` (tarball, not git clone — no submodules). Version `2.5.2`.
- **Motivation**: Trixie's `fluidsynth` package pulls in `libsdl2` (display deps, unacceptable for a headless image). We use the LV2 plugin only — no CLI binary needed. `libfluidsynth3` itself (the shared library) is fine and stays in `00-packages`; only the `fluidsynth` CLI package is avoided.
- **Scope**: `fluidsynth-headless` ships **only the CLI binary** built without SDL. It does NOT replace or conflict with `libfluidsynth3` — the library comes from Trixie apt as normal. This is purely a CLI-only package for debugging/testing.
- **cmake flags** (from pistomp-arch PKGBUILD, all critical):
  - `-Denable-sdl2=OFF -Denable-sdl3=OFF` — strips the SDL dep
  - `-Denable-jack=ON -Denable-alsa=ON -Denable-pulseaudio=ON -Denable-libsndfile=ON -Denable-dbus=ON`
  - `-Denable-ladspa=ON -Denable-portaudio=ON -Denable-readline=ON`
  - `-DLIB_SUFFIX=""`
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), cmake, libasound2-dev, libdbus-1-dev, libglib2.0-dev, libjack-jackd2-dev | libjack-dev, libpulse-dev, libreadline-dev, libsndfile1-dev, libfluidsynth-dev, portaudio19-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}, libfluidsynth3`
  - No Conflicts/Replaces — `libfluidsynth3` stays from Trixie apt
- **config.sh addition**: `FLUIDSYNTH_VERSION="2.5.2"` and `FLUIDSYNTH_URL="https://github.com/FluidSynth/fluidsynth/archive/v${FLUIDSYNTH_VERSION}.tar.gz"`.
- **build.sh note**: use `wget` / `curl` + `tar xf` instead of `git clone` since source is a tarball. Cache check: `fluidsynth-headless_2.5.2*_arm64.deb`.

---

## 9. lcd-splash

- **Source**: no upstream git clone needed. Pre-built arm64 binary already at `stage2/05-pistomp/files/sys/lcd-splash`. Splash image at `stage2/05-pistomp/files/splash.rgb565`.
- **Build approach**: no compilation. `build.sh` just assembles the `.deb` from the pre-built files.
  - Copy `stage2/05-pistomp/files/sys/lcd-splash` → `debian/lcd-splash/usr/bin/lcd-splash`
  - Copy `stage2/05-pistomp/files/splash.rgb565` → `debian/lcd-splash/usr/share/pistomp/splash.rgb565`
  - Run `dpkg-deb --build --root-owner-group debian/lcd-splash "${CACHE_DIR}/lcd-splash_1.0-2_arm64.deb"`
- **No `dpkg-buildpackage`** needed — this is a binary-only repackage. Use `dpkg-deb --build` directly to avoid needing a full `debian/` tree with `rules`, `compat`, `source/format`.
- **Minimal debian/ tree**: `debian/control` + `debian/lcd-splash/` staging tree only. No `rules`, no `changelog` (use `dpkg-deb` directly).
- **debian/control** (standalone, for `dpkg-deb`):
  ```
  Package: lcd-splash
  Version: 1.0-2
  Architecture: arm64
  Maintainer: pistomp <pistomp@example.com>
  Depends: liblgpio1 | liblgpio0
  Description: Fast ILI9341 LCD boot splash for pi-Stomp
  ```
- **build.sh**: idempotent check on `lcd-splash_1.0-2_arm64.deb` in `$CACHE_DIR`; no clone step; just stage + `dpkg-deb`.
- **Issues**: binary was compiled against `liblgpio` (the C library, not python3-rpi-lgpio). Verify the exact `.so` name with `ldd lcd-splash` and set `Depends` accordingly. The Trixie package name is `liblgpio-dev` / `liblgpio1`.

---

## 10. jack-capture

- **Source**: `https://github.com/kmatheussen/jack_capture.git` tag `0.9.73`. Version `0.9.73`.
- **Patches** (2 patches from pistomp-arch, apply via quilt):
  - `jack_capture-post-release-fixes.patch`
  - `jack_capture-file-rotation.patch`
  - Both in `debpkgs/jack-capture/debian/patches/` and listed in `series`.
  - Note: patches in pistomp-arch were applied via `git am` (format-patch style). Convert to plain unified diff format for quilt compatibility, or keep as-is and call `git am` in `debian/rules`'s `override_dh_auto_patch`.
  - Also apply the MacPorts path strip as a patch (or as an inline `sed` in `debian/rules` `override_dh_auto_patch`).
- **Build**: plain `make`. Install: `make PREFIX=/usr DESTDIR=... install` + install `jack_capture_gui` to `/usr/bin/`.
- **debian/control**:
  - Build-Depends: `debhelper-compat (= 13), libjack-jackd2-dev | libjack-dev, liblo-dev, libmp3lame-dev, libsndfile1-dev`
  - Depends: `${shlibs:Depends}, ${misc:Depends}, liblo7, libsndfile1, libmp3lame0`
- **config.sh addition**: `JACK_CAPTURE_REPO="https://github.com/kmatheussen/jack_capture.git"` and `JACK_CAPTURE_TAG="0.9.73"`.
- **Used for debugging** — not called by pi-Stomp services directly, but installed on the device for developer/debugging use. Add to the `apt install` block in `02-run.sh`.

---

## Changes to `02-run.sh`

**Approach:** modify `02-run.sh` incrementally as each debpkg is completed and confirmed working — do not defer all changes to 3e. Only remove a source-build block once its replacement (.deb in `cache/` or Trixie apt package) is ready. **Exception: jack-example-tools** is a plain Trixie apt install with no build step — its source-build block can be removed and `00-packages` updated right now, independently of any debpkg work.

### Blocks to delete (replaced by `apt install` from the custom apt repo)

Remove the following source-build blocks entirely from the `on_chroot` block:

| Lines (approx) | Block | Replacement |
| :--- | :--- | :--- |
| Hylia clone + make + make install | `[ ! -d Hylia ] && git clone ... ; cd Hylia ; make ; make install` | `apt-get install -y hylia` |
| jack2 clone + patch + waf | `[ ! -d jack2 ] && git clone ... ; cd jack2 ; git apply ... ; rm -rf waflib ; waf configure ; waf build ; waf install` | `apt-get install -y jack2-pistomp` |
| jack-example-tools clone + meson | `[ ! -d jack-example-tools ] && git clone ... ; meson setup ... ; ninja ... ; meson install` | add `jack-example-tools` to `stage2/05-pistomp/00-packages` — plain Trixie apt, no custom deb, no apt-get call in `02-run.sh` |
| amidithru clone + make install | `[ ! -d amidithru ] && git clone ... ; sed -i ... ; make install` | `apt-get install -y amidithru` |
| mod-host clone + make + make install | `[ ! -d mod-host ] && git clone ... ; make ; make install` | `apt-get install -y mod-host-pistomp` |
| mod-midi-merger clone + cmake | `[ ! -d mod-midi-merger ] && git clone ... ; sed -i ... ; mkdir build ; cmake ... ; make ; make install` | `apt-get install -y mod-midi-merger` |
| mod-ttymidi clone + make install | `[ ! -d mod-ttymidi ] && git clone ... ; make install` | `apt-get install -y mod-ttymidi` |

### Add `apt-get install` calls

After adding the pistomp apt repo source (e.g., in `01-run.sh` or at the top of `02-run.sh`'s chroot block), replace the deleted blocks with a single apt invocation:

```bash
apt-get install -y \
    hylia \
    jack2-pistomp \
    amidithru \
    mod-host-pistomp \
    mod-midi-merger \
    mod-ttymidi \
    sfizz-pistomp \
    fluidsynth-headless \
    lcd-splash
```

(`jack-example-tools` is absent — it comes from Trixie apt via `00-packages`, not the custom repo.)

### Also remove from `02-run.sh` / prerequisites

- Remove `pip3 install waf` (waf was only needed for jack2 source build; the custom `.deb` CI builds in an environment that has waf installed separately).
- Remove `install -m 644 files/patches/pi-controller-reset.patch "${ROOTFS_DIR}/tmp/"` and the `rm -f /tmp/pi-controller-reset.patch` cleanup — the patch is now applied at `.deb` build time, not image build time.
- Update service files: `mod-midi-merger.service` lines 9–10 change `/usr/local/bin/jack_load` → `/usr/bin/jack_load` and `/usr/local/bin/jack_unload` → `/usr/bin/jack_unload` (per PLAN-3b §4).

### fluidsynth-headless

`libfluidsynth3` and `libfluidsynth-dev` stay in `00-packages` from Trixie apt — `fluidsynth-headless` does not replace them. Only the Trixie `fluidsynth` CLI package is avoided (due to SDL deps).
