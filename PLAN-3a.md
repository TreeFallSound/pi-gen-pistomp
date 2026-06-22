# PLAN-3a: Infrastructure Skeleton

Infrastructure work that must exist before any individual debpkg can be added.

---

## Framing: two phases, one `config.sh`

`config.sh` is the single source of truth for all upstream dependencies, but its content evolves as packages mature:

**Phase 1 — package lives in `debpkgs/` here (monorepo):**
`config.sh` holds source refs — repo URL + tag/branch. `debpkgs/<pkg>/build.sh` clones and builds locally. `FORCE_REBUILD=1` bypasses the cache and rebuilds. This only works while `build.sh` lives in this repo.

**Phase 2 — package extracted to its own `TreeFallSound/<pkg>` repo:**
`debpkgs/<pkg>/` is deleted from this repo. `config.sh` replaces the source ref with an artifact version pin **and** the GitHub repo that hosts releases:
```bash
# Phase 1 (monorepo):
JACK2_REPO="https://github.com/jackaudio/jack2.git"
JACK2_TAG="v1.9.22"

# Phase 2 (external repo):
JACK2_DEB_REPO="TreeFallSound/jack2"   # GitHub org/repo hosting the release
JACK2_DEB_VERSION="1.9.22-1"          # exact release artifact version
```
`fetch-packages.sh` constructs the download URL as:
```
https://github.com/${JACK2_DEB_REPO}/releases/download/jack2-pistomp_${JACK2_DEB_VERSION}/jack2-pistomp_${JACK2_DEB_VERSION}_arm64.deb
```
A `scripts/fetch-packages.sh` wrapper handles both forms: if `debpkgs/<pkg>/build.sh` exists → build locally into `cache/`; otherwise → download using `_DEB_REPO` + `_DEB_VERSION` into `cache/`. `FORCE_REBUILD=1` re-downloads rather than rebuilds in phase 2.

During the transition, both forms coexist in `config.sh`. The fetch wrapper is the only thing that needs to know the difference.

---

## 1. `config.sh` — Centralised version pins

**File:** `/config.sh` (repo root, alongside `config`)

Source this in every script that clones or fetches upstream code.
Model: `pistomp-arch/config.sh`.

```bash
#!/bin/bash
# pistomp-gen build configuration — source this, do not execute.
# All upstream URLs, branches, and version pins live here.

# --- RT Kernel ---
KERNEL_VERSION="6.18.36"
KERNEL_LOCALVERSION="-rt-v8+"                          # suffix in uname -r
LINUX_RPI_COMMIT="954341c412dd48b7c7f8125d81212ec4c0e42ed3"

# --- JACK2 ---
JACK2_REPO="https://github.com/jackaudio/jack2.git"
JACK2_TAG="v1.9.22"

# --- jack-example-tools ---
JACK_EXAMPLE_TOOLS_REPO="https://salsa.debian.org/multimedia-team/jack-example-tools.git"
JACK_EXAMPLE_TOOLS_REF="debian/4-4"

# --- Hylia ---
HYLIA_REPO="https://github.com/falkTX/Hylia.git"
HYLIA_REF="master"                                     # no stable tag; pin by commit when needed

# --- mod-host ---
MOD_HOST_REPO="https://github.com/sastraxi/mod-host.git"
MOD_HOST_BRANCH="fix/effect-drain-midi"

# --- mod-ui ---
MODUI_REPO="https://github.com/TreeFallSound/mod-ui.git"
MODUI_BRANCH="master"

# --- browsepy ---
BROWSEPY_REPO="https://github.com/micahvdm/browsepy.git"
BROWSEPY_REF="master"

# --- amidithru ---
AMIDITHRU_REPO="https://github.com/BlokasLabs/amidithru.git"
AMIDITHRU_REF="master"

# --- touchosc2midi ---
TOUCHOSC2MIDI_REPO="https://github.com/BlokasLabs/touchosc2midi.git"
TOUCHOSC2MIDI_REF="master"

# --- mod-midi-merger ---
MOD_MIDI_MERGER_REPO="https://github.com/mod-audio/mod-midi-merger.git"
MOD_MIDI_MERGER_REF="master"

# --- mod-ttymidi ---
MOD_TTYMIDI_REPO="https://github.com/moddevices/mod-ttymidi.git"
MOD_TTYMIDI_REF="master"

# --- pi-stomp (application) ---
PISTOMP_REPO="https://github.com/TreeFallSound/pi-stomp.git"
PISTOMP_BRANCH="pistomp-v3"

# --- Pedalboards / user files ---
PEDALBOARDS_REPO="https://github.com/TreeFallSound/pi-stomp-pedalboards.git"
PEDALBOARDS_BRANCH="master"

USERFILES_REPO="https://github.com/TreeFallSound/pi-stomp-user-files.git"
USERFILES_BRANCH="main"

# --- LV2 plugins tarball ---
LV2_PLUGINS_URL="https://www.treefallsound.com/downloads/lv2plugins.tar.gz"
LV2_PLUGINS_SHA256=""

# --- Python (uv-managed, for mod-ui venv only) ---
MOD_UI_PYTHON_VERSION="3.11"

# --- apt repo (GitHub Pages) ---
APT_REPO_SUITE="trixie"
APT_REPO_COMPONENT="main"
APT_REPO_ARCH="arm64"
```

**Rationale:** single source of truth mirrors pistomp-arch; version bumps require one-line edits with no script archaeology.

---

## 2. `debpkgs/` directory convention

**Root:** `/debpkgs/`

Each package: `debpkgs/<pkg-name>/build.sh` + `debpkgs/<pkg-name>/debian/`

### `build.sh` contract

- Sourced variables from `config.sh` (caller's responsibility to source it first, or `build.sh` sources `../../config.sh` itself when run standalone).
- `CACHE_DIR` defaults to `../../cache/` when unset; CI always sets it explicitly.
- Clones upstream source, drops in `debian/` tree, runs `dpkg-buildpackage -b -us -uc`.
- Outputs `.deb` files to `$CACHE_DIR`.
- Does **not** run `dpkg -i` — installation is the image builder's job.
- Must be idempotent (skip clone if directory exists; check for existing `.deb` in `$CACHE_DIR` and exit-0 if present and `FORCE_REBUILD` is unset).

### Template `build.sh`

```bash
#!/bin/bash
# Build <PKG> .deb for arm64 Debian Trixie.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source version pins (idempotent if already sourced by caller)
# shellcheck source=../../config.sh
source "${ROOT_DIR}/config.sh"

PKG="<pkg-name>"
VERSION="${<PKG>_TAG:-${<PKG>_REF}}"      # whichever var applies
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
UPSTREAM_DIR="${WORKDIR:-/tmp}/${PKG}-src"

mkdir -p "${CACHE_DIR}"

# Skip if already built
if ls "${CACHE_DIR}/${PKG}_${VERSION}"*_arm64.deb &>/dev/null && [[ -z "${FORCE_REBUILD:-}" ]]; then
    echo "==> ${PKG} already in cache, skipping."
    exit 0
fi

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${VERSION}" --recurse-submodules \
        "${<PKG>_REPO}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc

# Move output debs to cache
find "$(dirname "${UPSTREAM_DIR}")" -maxdepth 1 -name "${PKG}_*.deb" \
    -exec mv {} "${CACHE_DIR}/" \;

echo "==> Built ${PKG} → ${CACHE_DIR}"
```

### Initial packages under `debpkgs/`

Packages currently built inline in `02-run.sh` that are good candidates to extract:

| Package | Reason to debpkg |
| :--- | :--- |
| `jack2-pistomp` | Carries a patch; benefits from `.deb` cache |
| `mod-host-pistomp` | Fork pinned to a branch |
| `hylia-pistomp` | No upstream `.deb`; stable binary |

The remaining packages (amidithru, mod-midi-merger, mod-ttymidi, touchosc2midi) are lower priority but follow the same pattern.

---

## 3. `cache/` directory

**Path:** `/cache/`

- Add `/cache/` to `.gitignore` (already has `deploy/` pattern — add alongside it).
- The existing `stage2/05-pistomp/files/sys/` kernel `.deb` staging area stays as-is for now; the cache concept is unified conceptually but the kernel build script's `CACHE_DIR` already points there. Future: unify by pointing `build-rt-kernel-docker.sh`'s `CACHE_DIR` default to `/cache/` and symlinking or copying into `files/sys/` at image build time.
- `.gitignore` addition:

```
# Built .deb cache (populated by debpkgs/*/build.sh and build-rt-kernel-docker.sh)
cache/
```

---

## 4. GitHub Actions workflow template per debpkg

**Path pattern:** `.github/workflows/build-<pkg>.yml`

One workflow per package. Trigger: push to `debpkgs/<pkg>/**` or `config.sh`.
Runner: `ubuntu-24.04-arm` (native arm64, no QEMU, no cross-compilation needed).

### Template `.github/workflows/build-jack2-pistomp.yml`

```yaml
name: build-jack2-pistomp

on:
  push:
    branches: [pistomp-v3]
    paths:
      - 'debpkgs/jack2-pistomp/**'
      - 'config.sh'
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4

      - name: Install build dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            dpkg-dev devscripts debhelper-compat \
            libjack-dev libsamplerate0-dev libsndfile1-dev \
            pkg-config python3

      - name: Build .deb
        run: |
          source config.sh
          WORKDIR=/tmp CACHE_DIR=${{ github.workspace }}/cache \
            bash debpkgs/jack2-pistomp/build.sh

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: jack2-pistomp-deb
          path: cache/*.deb
          if-no-files-found: error

      - name: Publish to GitHub Releases
        if: github.event_name == 'push'
        uses: softprops/action-gh-release@v2
        with:
          tag_name: debpkg/jack2-pistomp/${{ env.PKG_VERSION }}
          name: "jack2-pistomp ${{ env.PKG_VERSION }}"
          files: cache/*.deb
          draft: false
          prerelease: false
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

**Note on `PKG_VERSION`:** add a step before publish to extract the version from `config.sh` and export it: `echo "PKG_VERSION=${JACK2_TAG}" >> $GITHUB_ENV`.

**Decision:** use per-package workflows (not a matrix) so each package can declare its own `apt-get` build-deps without a giant combined list. Trigger on `config.sh` changes so a version bump rebuilds all affected packages via separate workflow files.

---

## 5. apt repo on GitHub Pages

### Branch and directory structure

- Branch: `gh-pages`
- Layout:

```
pool/
  main/
    jack2-pistomp_1.9.22-1_arm64.deb
    mod-host-pistomp_<ver>_arm64.deb
    ...
dists/
  trixie/
    Release
    main/
      binary-arm64/
        Packages
        Packages.gz
```

### `publish-apt-repo.yml` workflow

**Path:** `.github/workflows/publish-apt-repo.yml`

Trigger: `release` event (published) — runs after any debpkg release uploads its `.deb`.

```yaml
name: publish-apt-repo

on:
  release:
    types: [published]
  workflow_dispatch:

jobs:
  publish:
    runs-on: ubuntu-24.04-arm
    steps:
      - uses: actions/checkout@v4
        with:
          ref: gh-pages
          fetch-depth: 0

      - name: Download all release assets
        run: |
          gh release list --repo ${{ github.repository }} --limit 50 \
            --json tagName,assets \
            | jq -r '.[].assets[].browserDownloadUrl' \
            | grep '_arm64\.deb$' \
            | xargs -I{} wget -q -P pool/main/ {} 2>/dev/null || true
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Rebuild Packages index
        run: |
          mkdir -p dists/trixie/main/binary-arm64
          dpkg-scanpackages --arch arm64 pool/main/ \
            > dists/trixie/main/binary-arm64/Packages
          gzip -9 -k dists/trixie/main/binary-arm64/Packages

      - name: Write Release file
        run: |
          apt-ftparchive release \
            -o APT::FTPArchive::Release::Origin="pistomp" \
            -o APT::FTPArchive::Release::Label="pistomp" \
            -o APT::FTPArchive::Release::Suite="trixie" \
            -o APT::FTPArchive::Release::Codename="trixie" \
            -o APT::FTPArchive::Release::Architectures="arm64" \
            -o APT::FTPArchive::Release::Components="main" \
            dists/trixie/ > dists/trixie/Release

      - name: Commit and push
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add pool/ dists/
          git diff --cached --quiet && echo "No changes" && exit 0
          git commit -m "apt: rebuild index $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          git push origin gh-pages
```

### apt source entry (installed in image)

Add to stage2 run script (see §7):

```
deb [arch=arm64 trusted=yes] https://<org>.github.io/<repo> trixie main
```

**Decision:** unsigned (`trusted=yes`) for now — avoids key management complexity. Re-evaluate when the repo goes public.

**Decision:** `dpkg-scanpackages` + `apt-ftparchive` from `dpkg-dev` / `apt-utils` (both pre-installed on `ubuntu-24.04-arm` runners). No third-party action needed.

---

## 6. Sudoers entry for pistomp-recovery

**Mechanism:** install a drop-in sudoers file via a stage2 run script.

**File to install:** `stage2/05-pistomp/files/pistomp-nopasswd.sudoers`

```
# Allow the pistomp user to run package management without a password.
# Required by pistomp-recovery to perform OTA upgrades.
pistomp ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/dpkg, /usr/bin/apt
```

**Install in:** `stage2/05-pistomp/03-run.sh` (already installs misc system files), outside the `on_chroot` block:

```bash
install -m 440 files/pistomp-nopasswd.sudoers \
    "${ROOTFS_DIR}/etc/sudoers.d/pistomp-nopasswd"
```

**Decision:** drop-in under `/etc/sudoers.d/` (not editing `/etc/sudoers`) — safer, easier to audit, survives `sudo` package updates.

---

## 7. `02-run.sh` sourcing of `config.sh`

**What to change (plan only — do not implement here):**

- At the top of `stage2/05-pistomp/02-run.sh`, after the shebang:
  ```bash
  # shellcheck source=../../config.sh
  source "$(dirname "${BASH_SOURCE[0]}")/../../config.sh"
  ```
- Replace each hardcoded URL/branch/tag with the corresponding variable from `config.sh`:

| Current hardcoded value | Replace with |
| :--- | :--- |
| `https://github.com/jackaudio/jack2.git` / `v1.9.22` | `$JACK2_REPO` / `$JACK2_TAG` |
| `https://salsa.debian.org/.../jack-example-tools.git` / `debian/4-4` | `$JACK_EXAMPLE_TOOLS_REPO` / `$JACK_EXAMPLE_TOOLS_REF` |
| `https://github.com/falkTX/Hylia.git` | `$HYLIA_REPO` |
| `https://github.com/micahvdm/browsepy.git` | `$BROWSEPY_REPO` |
| `https://github.com/sastraxi/mod-host.git` / `fix/effect-drain-midi` | `$MOD_HOST_REPO` / `$MOD_HOST_BRANCH` |
| `https://github.com/TreeFallSound/mod-ui.git` | `$MODUI_REPO` |
| `https://github.com/BlokasLabs/amidithru.git` | `$AMIDITHRU_REPO` |
| `https://github.com/BlokasLabs/touchosc2midi.git` | `$TOUCHOSC2MIDI_REPO` |
| `https://github.com/mod-audio/mod-midi-merger` | `$MOD_MIDI_MERGER_REPO` |
| `https://github.com/moddevices/mod-ttymidi.git` | `$MOD_TTYMIDI_REPO` |

- `build-rt-kernel-docker.sh` also has kernel version inline — replace with `$KERNEL_VERSION`, `$KERNEL_LOCALVERSION`, `$LINUX_RPI_COMMIT` from `config.sh`. The script already uses a `CACHE_DIR` variable so no structural change needed there.

---

## Implementation order

Steps 1–4 are in scope for 3a. Steps 5–9 are deferred.

1. Create `config.sh` (§1) — unblocks everything else.
2. Add `cache/` to `.gitignore` (§3).
3. Create `debpkgs/` skeleton (§2) — directory + README stub + template `build.sh` + template `build.yml` (under `debpkgs/template/`, not under `.github/workflows/`).
4. Create `stage2/05-pistomp/files/pistomp-nopasswd.sudoers` and add install line to `03-run.sh` (§6).
5. _(deferred to 3e)_ Wire `02-run.sh` to source `config.sh` and replace hardcoded values (§7).
6. _(deferred to 3e)_ Wire `build-rt-kernel-docker.sh` to source `config.sh`.
7. _(deferred to 3e)_ Create `gh-pages` branch with empty `pool/main/` and placeholder `dists/` (§5).
8. _(deferred to 3e)_ Create `.github/workflows/publish-apt-repo.yml` (§5).
9. _(deferred to 3c)_ Create first debpkg — that is 3c work, not 3a.

**`scripts/fetch-packages.sh`:** Create as a Phase 1 skeleton alongside step 1. Phase 2 download logic (`_DEB_REPO`/`_DEB_VERSION`) is a `# TODO` stub only.
