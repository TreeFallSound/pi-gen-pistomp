# OTA Updates via GitHub Pages apt Repository

pistompOS devices receive package updates via a GitHub Pages-hosted apt
repository. Pushing a change to `debpkgs/<pkg>/` on `main` triggers a CI
build, publishes the `.deb` as a GitHub Release, and rebuilds the apt index
on `gh-pages` — all automatically.

## Pipeline

```
push debpkgs/<pkg>/**  →  build-<pkg>.yml  →  GitHub Release (debpkg/<pkg>/<ver>)
                                                ↓
                       publish-apt-repo.yml  →  gh-pages branch (reprepro index)
                                                ↓
device /etc/apt/sources.list.d/pistomp.list  →  apt update  →  apt upgrade <pkg>
```

## Workflows

| File | Trigger | What it does |
| :--- | :--- | :--- |
| `.github/workflows/build-deb.yml` | `workflow_call` | Reusable: extract version from `debian/changelog`, install `Build-Depends` automatically (apt then GitHub Releases fallback, up to 5 passes), run `build.sh`, publish a Release tagged `debpkg/<pkg>/<ver>`. On PRs, fails if that tag already exists. |
| `.github/workflows/build-<pkg>.yml` | push/PR on `debpkgs/<pkg>/**` or `config.sh` | Thin wrapper calling `build-deb.yml`. One file per package. Template at `docs/package-template/build.yml`. |
| `.github/workflows/publish-apt-repo.yml` | `release: published` or `workflow_dispatch` | Downloads every `*_arm64.deb` release asset, `reprepro includedeb trixie` (refuses duplicate name+version), commits `pool/`+`dists/`+`conf/` to `gh-pages`. Self-bootstraps the orphan branch on first run. |

All 19 packages have a `build-<pkg>.yml` workflow.

## Build-time vs runtime apt sources

The image build installs custom packages directly from the GitHub Pages apt
repo — no local package building required. `stage2/00-dummy-packages/01-run.sh`
writes `pistomp.list` pointing at `APT_REPO_URL` (defined in `config.sh`) as
the primary source.

If `cache/debpkgs/` contains locally-built `.deb` overrides (produced by
`build-package-docker.sh`), `build-docker.sh` runs `scripts/setup-apt-repo.sh`
first to generate `cache/apt-repo/`, and `01-run.sh` adds it as a
higher-priority source (`Pin-Priority: 1001`) via `pistomp-local.list`. This
lets you test a locally-modified package without publishing a release.

`stage2/05-pistomp/05-run.sh` removes the local override files
(`pistomp-local.list` and the preferences pin) before the image is
finalized. The final image carries only `pistomp.list` pointing at
`APT_REPO_URL` — no dead `file://` source, OTA works out of the box.

## Version gate: `debian/changelog` is the only trigger

**Nothing is published unless you bump the version in `debian/changelog`.**
The CI extracts the version from the changelog, tags the release
`debpkg/<pkg>/<version>`, and the three gates below all key off that tag.
If the tag already exists, nothing is pushed to GitHub Releases or `gh-pages`.

```bash
./scripts/bump-version.sh <pkg> "Description of change."
```

### Duplicate-version protection (three layers)

1. **PR check** — `build-deb.yml` queries for an existing `debpkg/<pkg>/<ver>`
   release and fails the status check before merge.
2. **Release tag** — `softprops/action-gh-release` gets HTTP 422 from GitHub
   if the tag exists.
3. **`reprepro includedeb`** — refuses to add a package whose name+version is
   already in the repo; `gh-pages` is only updated when something changed.

## Packages

All 19 custom `.deb` packages have CI workflows and are published to the repo:

| Package | Notes |
| :--- | :--- |
| `hylia` | Plain make; no pistomp deps |
| `jack2-pistomp` | waf, libdb5.3-dev, quilt |
| `mod-host-pistomp` | Build-dep on `hylia` (fetched from Releases automatically) |
| `amidithru` | libasound2-dev |
| `mod-midi-merger` | cmake, libjack-dev |
| `mod-ttymidi` | libjack-dev, libasound2-dev |
| `sfizz-pistomp` | cmake, lv2-dev, libsamplerate0-dev |
| `fluidsynth-headless` | cmake, many audio libs |
| `lcd-splash` | Binary-only (`dpkg-deb`); build-dep on `lg` (fetched from Releases) |
| `lg` | lgpio; needed at compile time by `lcd-splash` |
| `jack-capture` | libjack-dev, libsndfile1-dev, liblo-dev |
| `libfluidsynth2-compat` | Symlink shim (`dpkg-deb`); no build deps |
| `browsepy` | python3, uv |
| `touchosc2midi` | python3, uv, Cython<3.1, pyliblo3 |
| `mod-ui` | python3, uv, make, libjack-dev |
| `pi-stomp` | python3, uv |
| `pistomp-recovery` | python3, uv, swig, SDL2/freetype headers |
| `jackbridge` | Shell scripts only; git |
| `ffmpeg-pistomp` | cmake, many codec libs |

## Adding a new package to OTA

1. Create `debpkgs/<pkg>/` with `build.sh`, `debian/`, and a `debian/changelog` entry.
2. Add the package to `stage2/05-pistomp/02-run.sh`'s `apt-get install` list (factory baseline).
3. Copy `docs/package-template/build.yml` → `.github/workflows/build-<pkg>.yml`, changing the name, `paths:` filter, and `pkg:` input.
4. Bump `debian/changelog`, push to `main`, watch the two workflows run.

## Testing a local package build

```bash
./build-package-docker.sh <pkg>
# .deb lands in cache/debpkgs/
./build-docker.sh -f
# image build uses it via the high-priority local override
```

Remove the `.deb` from `cache/debpkgs/` to revert to the published version.

## Staleness check for branch-pinned packages

Packages pinned to an upstream branch (those with `_BRANCH` or `_REF` in
`config.sh`) can accumulate new commits silently — the changelog version is
unchanged, the published `.deb` is cached, and old code ships. Run the
staleness check manually before deciding whether to cut a new release:

```bash
./scripts/check-upstream-staleness.sh
```

This reports the current HEAD SHA of each upstream branch/ref alongside the
latest published release version. It does not build or push anything.

## One-time setup (GitHub Pages)

The `publish-apt-repo.yml` workflow creates the `gh-pages` branch on first
run. After the first workflow run, enable Pages:

> Repo Settings → Pages → Source → Deploy from a branch → `gh-pages` / `/(root)`

## Upgrading a pre-OTA device

Devices flashed before `pistomp.list` was baked in need the source added once:

```bash
ssh pistomp@pistomp.local
echo "deb [arch=arm64 trusted=yes] https://treefallsound.github.io/pi-gen-pistomp trixie main" \
  | sudo tee /etc/apt/sources.list.d/pistomp.list
sudo apt-get update
sudo apt-get install --only-upgrade pistomp-recovery
```

If a stale `file:/pistomp-cache/apt-repo` source is present, remove it first:

```bash
sudo rm -f /etc/apt/sources.list.d/pistomp-local.list
```

## GPG signing (future)

The `trusted=yes` flag skips signature verification. To sign the repo later:

1. Generate a GPG key and export the public key to `pistomp-archive-keyring.gpg`.
2. Install the keyring during image build (`stage2/05-pistomp/01-run.sh`).
3. Change the source line to `signed-by=/usr/share/keyrings/pistomp-archive-keyring.gpg`.
4. Sign `dists/trixie/Release` in `publish-apt-repo.yml` with `gpg --detach-sign`.
