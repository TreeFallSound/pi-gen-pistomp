# OTA Updates via GitHub Pages apt Repository

This document describes how to enable over-the-air package updates on
pistompOS devices using a GitHub Pages-hosted apt repository.

## Current state

Factory images install custom `.deb` packages via `dpkg -i` from a
build-time cache (`stage2/05-pistomp/02-run.sh`). There is no apt source
entry on the device, so `apt update`, `apt upgrade`, and
pistomp-recovery's `apt-get install <pkg>` cannot find newer versions.

To enable OTA, the device needs an apt source pointing at a repository
that serves the latest `.deb` files. GitHub Pages can host this for free.

## Architecture

```
 pi-gen-pistomp repo                GitHub Pages (gh-pages branch)
 ─────────────────                  ────────────────────────────────
 debpkgs/*/build.sh  ──build──▶  pool/main/<pkg>_<ver>_arm64.deb
                                          │
 .github/workflows/                 dists/trixie/
   publish-apt-repo.yml  ─────▶      Release
                                          main/binary-arm64/
                                            Packages
                                            Packages.gz
                                          │
 Device  ◀──────── https://<org>.github.io/<repo> trixie main
 /etc/apt/sources.list.d/pistomp.list
```

## Step 1 — Per-package build workflows

Each package under `debpkgs/` needs a thin workflow that triggers on
changes to that package's files and calls a shared reusable workflow.
The build logic (version extraction, duplicate check, build-dep
installation, release publishing) lives once in
`.github/workflows/build-deb.yml`. Each per-package workflow is ~15
lines.

### Reusable workflow (already in the repo)

`.github/workflows/build-deb.yml` is a `workflow_call` workflow that:
- Extracts the version from `debian/changelog` (or `debian/control` for
  binary-only packages).
- On PRs, checks if a GitHub Release tag for that version already exists
  (fails the PR check if it does).
- Parses `Build-Depends` from `debian/control` and installs them
  automatically — no per-package dep list to maintain.
- Runs `debpkgs/<pkg>/build.sh`.
- On push to `pistomp-v3`, publishes the `.deb` as a GitHub Release
  asset tagged `debpkg/<pkg>/<version>`.

### Per-package workflow

Create `.github/workflows/build-<pkg>.yml` (template at
`debpkgs/template/build.yml`):

```yaml
name: build-jack2-pistomp

on:
  push:
    branches: [pistomp-v3]
    paths:
      - 'debpkgs/jack2-pistomp/**'
      - 'config.sh'
  pull_request:
    paths:
      - 'debpkgs/jack2-pistomp/**'
      - 'config.sh'
  workflow_dispatch:

jobs:
  build:
    uses: ./.github/workflows/build-deb.yml
    with:
      pkg: jack2-pistomp
    secrets: inherit
```

That's the entire per-package workflow — change the name, the path
filter, and the `pkg` input. The reusable workflow handles everything
else.

**Notes:**

- `ubuntu-24.04-arm` runners are native arm64 — no QEMU, no
  cross-compilation.
- Build dependencies are parsed from `debian/control` at runtime, so
  adding a new `Build-Depends` line to a package's control file is all
  that's needed — no workflow edit required.
- Binary-only packages (`lcd-splash`, `libfluidsynth2-compat`) have no
  `Build-Depends` in `debian/control`; the install step detects this and
  skips.
- Packages with build-time dependencies on other pistomp packages (e.g.
  `mod-host-pistomp` depends on `hylia`) need a pre-build step to
  download and install the dependency's `.deb` from Release assets. Add
  this to the per-package workflow after the `uses:` call is not
  possible (reusable workflows can't be extended), so instead add the
  hylia download as a step in a wrapper workflow, or add a
  `pre-build.sh` hook convention in `build.sh` itself. Simplest: have
  `build.sh` download its own build deps from GitHub Releases if not
  installed locally.

## Step 2 — Publish-apt-repo workflow

This workflow runs after any package release. It downloads all `*_arm64.deb`
release assets, uses `reprepro` to add them to the apt repo (which refuses
duplicate name+version by default), and pushes the result to the
`gh-pages` branch.

Create `.github/workflows/publish-apt-repo.yml`:

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

      - name: Install reprepro
        run: sudo apt-get install -y reprepro

      - name: Download all release assets
        run: |
          mkdir -p pool/main
          gh release list --repo ${{ github.repository }} --limit 100 \
            --json tagName,assets \
            | jq -r '.[].assets[].browserDownloadUrl' \
            | grep '_arm64\.deb$' \
            | xargs -I{} wget -q -P pool/main/ {} 2>/dev/null || true
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}

      - name: Add packages to repo (refuses duplicate name+version)
        run: |
          for deb in pool/main/*.deb; do
            reprepro -b . includedeb trixie "$deb"
          done

      - name: Commit and push
        run: |
          git config user.name  "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add pool/ dists/
          git diff --cached --quiet && echo "No changes" && exit 0
          git commit -m "apt: rebuild index $(date -u +%Y-%m-%dT%H:%M:%SZ)"
          git push origin gh-pages
```

**Prerequisite:** Enable GitHub Pages for the repository, set to serve
from the `gh-pages` branch root. Do this once in
Settings → Pages → Source → Deploy from a branch → `gh-pages` / `/(root)`.

**Prerequisite:** Create a `reprepro` config in the `gh-pages` branch
root (one-time setup, committed alongside the repo):

```
# conf/distributions
Origin: pistomp
Label: pistomp
Suite: trixie
Codename: trixie
Architectures: arm64
Components: main
Description: pi-Stomp custom packages
```

### Duplicate version prevention

Three independent gates, each catching unbumped versions at a different
stage:

1. **PR check (before merge):** The `Check version bumped` step in the
   build workflow runs on `pull_request`. It extracts the version from
   `debian/changelog` (or `config.sh` for pinned packages) and checks
   if a GitHub Release tag `debpkg/<pkg>/<version>` already exists. If
   so, the PR check fails — the developer sees a red status check with a
   message to bump the version.

2. **Release tag (at push to branch):** The build workflow's
   `softprops/action-gh-release` step creates a GitHub Release tagged
   `debpkg/<pkg>/<version>`. GitHub refuses to create a tag that already
   exists (HTTP 422). This catches anything that slipped past the PR
   check (e.g. a direct push without a PR).

3. **`reprepro includedeb` (at publish time):** `reprepro` refuses to
   add a package if the same name+version already exists in the repo:
   ```
   ERROR: Could not add 'pool/main/jack2-pistomp_1.9.22-1_arm64.deb':
   Already have package jack2-pistomp version 1.9.22-1 in trixie.
   ```
   The publish workflow fails, `gh-pages` is not updated, and the
   device never sees the stale version.

All three fail loudly with messages pointing at the version source
(`debian/changelog` or `config.sh`). To update a package, the developer
must increment the version — `reprepro` then automatically supersedes
the old version in the repo index.

## Step 3 — apt source entry on the device

Add the apt source during image build. In `stage2/05-pistomp/02-run.sh`,
before the `dpkg -i` block (or replacing it once the repo is live):

```bash
# Pistomp apt repo (GitHub Pages)
echo "deb [arch=arm64 trusted=yes] https://treefallsound.github.io/pi-gen-pistomp trixie main" \
    > /etc/apt/sources.list.d/pistomp.list
apt-get update -qq
```

Then replace the `dpkg -i /pistomp-cache/*.deb` block with:

```bash
apt-get install -y \
    hylia \
    jack2-pistomp \
    mod-host-pistomp \
    amidithru \
    mod-midi-merger \
    mod-ttymidi \
    sfizz-pistomp \
    fluidsynth-headless \
    lcd-splash \
    jack-capture \
    libfluidsynth2-compat \
    browsepy \
    touchosc2midi \
    mod-ui \
    pi-stomp \
    pistomp-recovery \
    jackbridge
```

`apt-get install` resolves dependencies automatically (unlike `dpkg -i`),
so ordering doesn't matter and `apt-get install -f` is no longer needed.

### Transition strategy

You don't have to switch all at once. Keep `dpkg -i` for the factory
image build (it's faster and works offline), and add the apt source entry
so devices can `apt update && apt upgrade` to pull newer versions later.
Both approaches coexist — `dpkg -i` installs the baseline, the apt source
provides the upgrade path.

## Step 4 — GPG signing (optional, later)

The `trusted=yes` in the source line tells apt to skip signature
verification. This is fine while the repo is private or experimental.
To sign the repo later:

1. Generate a GPG key for the repo.
2. Export the public key and install it on the device during image build:
   ```bash
   # In stage2/05-pistomp/01-run.sh:
   install -m 644 files/pistomp-archive-keyring.gpg \
       "${ROOTFS_DIR}/usr/share/keyrings/pistomp-archive-keyring.gpg"
   ```
3. Change the source line to use `signed-by`:
   ```
   deb [arch=arm64 signed-by=/usr/share/keyrings/pistomp-archive-keyring.gpg] \
       https://treefallsound.github.io/pi-gen-pistomp trixie main
   ```
4. Sign the `Release` file in the publish workflow with `apt-ftparchive`
   using `gpg`:
   ```bash
   gpg --batch --yes --armor --detach-sign --output dists/trixie/InRelease dists/trixie/Release
   ```

## How it works end-to-end

1. **Developer pushes** a change to `debpkgs/jack2-pistomp/**` or
   `config.sh` on `pistomp-v3`.
2. **`build-jack2-pistomp` workflow** runs on an arm64 runner, builds the
   `.deb`, publishes it as a GitHub Release asset tagged
   `debpkg/jack2-pistomp/<version>`.
3. **`publish-apt-repo` workflow** triggers on the release, downloads all
   `.deb` release assets, `reprepro includedeb` adds them to the repo
   (refusing duplicate name+version), pushes to `gh-pages`.
4. **GitHub Pages** serves the repo at
   `https://treefallsound.github.io/pi-gen-pistomp`.
5. **Device** runs `apt update` (or pistomp-recovery does it
   automatically), sees the new version, runs `apt upgrade jack2-pistomp`
   (or pistomp-recovery's UI installs it).

## Packages to publish

All 16 custom `.deb` packages under `debpkgs/`:

| Package | Build-deps notes |
| :--- | :--- |
| `hylia` | None (plain make) |
| `jack2-pistomp` | waf, libdb5.3-dev, quilt |
| `mod-host-pistomp` | Needs `hylia` .deb installed first |
| `amidithru` | libasound2-dev |
| `mod-midi-merger` | cmake, libjack-dev |
| `mod-ttymidi` | libjack-dev, libasound2-dev |
| `sfizz-pistomp` | cmake, lv2-dev, libsamplerate0-dev |
| `fluidsynth-headless` | cmake, many audio libs |
| `lcd-splash` | None (binary-only, `dpkg-deb`) |
| `jack-capture` | libjack-dev, libsndfile1-dev, liblo-dev |
| `libfluidsynth2-compat` | None (symlink shim, `dpkg-deb`) |
| `browsepy` | python3, uv |
| `touchosc2midi` | python3, uv, Cython<3.1, pyliblo3 |
| `mod-ui` | python3, uv, make, libjack-dev |
| `pi-stomp` | python3, uv |
| `pistomp-recovery` | python3, uv, swig, SDL2/freetype headers |
| `jackbridge` | git only (shell scripts, no compilation) |

## Local repo for testing

Before setting up CI, you can test the apt source locally by building
all `.deb` files and serving them from a directory:

```bash
# Build all packages
CACHE_DIR=./cache ./scripts/fetch-packages.sh

# Create reprepro config
mkdir -p /tmp/pistomp-repo/conf
cat > /tmp/pistomp-repo/conf/distributions <<'EOF'
Origin: pistomp
Label: pistomp
Suite: trixie
Codename: trixie
Architectures: arm64
Components: main
Description: pi-Stomp custom packages
EOF

# Add all .debs (reprepro refuses duplicate name+version)
cd /tmp/pistomp-repo
for deb in /path/to/cache/*.deb; do
    reprepro includedeb trixie "$deb"
done

# Serve (e.g. via Python)
python3 -m http.server 8080

# On the device:
echo "deb [arch=arm64 trusted=yes] http://<host-ip>:8080 trixie main" \
    > /etc/apt/sources.list.d/pistomp.list
apt-get update
apt-get install --only-upgrade jack2-pistomp
```