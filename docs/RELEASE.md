# Manual Release Process

## Build a test package locally

```bash
./build-package-docker.sh jack2-pistomp      # builds .deb → cache/debpkgs/
./build-docker.sh -f                          # full image uses the local .deb override
```

Remove the `.deb` from `cache/debpkgs/` to revert to the published version.

## Build a full image locally

```bash
./build-rt-kernel-docker.sh                   # once per kernel version bump
IMG_VERSION=3.0.0 ./build-docker.sh -f        # produces deploy/pistompOS-3.0.0.img
./compress-img.sh                             # produces deploy/pistompOS-3.0.0.img.xz
```

## Publish a release

### Current flow (automatic via `build-image.yml`)

The image build is triggered by **pushing a `release/<version>` tag**. The
workflow (`build-image.yml`) builds the image, publishes a GitHub Release
with the `.img.xz` and Imager manifest attached, and deploys the manifest
to `gh-pages` so Raspberry Pi Imager 2.x picks it up automatically.

```bash
# Production image:
git tag release/3.3.0 && git push origin release/3.3.0

# Pre-release image (testing channel — installs from + ships trixie-testing apt suite,
# flagged as GitHub prerelease, excluded from releases/latest):
git tag release/3.3.0-rc1 && git push origin release/3.3.0-rc1
```

The `_version_` becomes the image filename, release name and manifest URL
verbatim — **don't prefix it with `v`** (e.g. `release/v3.3.0` produces
`pistompOS-v3.3.0.img.xz`, which is non-conventional).

The prerelease flag is decided by a regex match on the version suffix:
`-(rc|pre|beta|alpha)[0-9]*$` → testing channel + GitHub prerelease. Plain
version → production channel + standard release.

Before tagging, **wait for all `build-<pkg>.yml` and `publish-apt-repo.yml`
runs from your last merge to `main` to finish** — the image build installs
`.deb`s from the live `gh-pages` apt repo, so any package published by a
recent merge must already be in the apt index when the image build runs.
The staleness gate (`check-upstream-staleness.sh`) only verifies that GitHub
Releases exist with current `.built-sha` sidecars; the image's actual
`apt-get install` reads the apt index, not GitHub Releases.

### Pre-merge PR check

`validate-packages.yml` runs `scripts/validate-packages.sh` on every PR
and is meant to be a required status check on `main`. It catches four
landmines (missing workflow for an installed package, unbumped changelog,
new package without workflow, stale workflow `paths:` typo) *before* merge
rather than at image build time.

### Manual dispatch (no release)

`build-image.yml` also accepts `workflow_dispatch` for test builds — those
produce a workflow artifact only, no GitHub Release and no manifest deploy.

### Imager manifest URLs

Two channel manifests plus per-version archival snapshots are kept on gh-pages:

| URL | Contents |
| --- | --- |
| `https://treefallsound.github.io/pi-gen-pistomp/imager/pistomp-stable.json` | Latest production image |
| `https://treefallsound.github.io/pi-gen-pistomp/imager/pistomp-testing.json` | Latest pre-release image |
| `https://treefallsound.github.io/pi-gen-pistomp/imager/pistomp-<version>.json` | Pinned to one version |
| `https://treefallsound.github.io/pi-gen-pistomp/imager/pistomp.json` | **Legacy** — mirrors stable. Never delete. |

Enter the stable or testing URL in Imager → App Options → Content Repository → Custom URL.

`pistomp.json` was the only URL the README published before channels existed, so
an unknown number of users already have it pasted into their Imager config.
`deploy-manifest` keeps writing it alongside `pistomp-stable.json`; removing it
would 404 every one of those installs on next launch, with nothing to tell them
why. It costs one file.

### Historical note

The manual `gh release create` + `git push gh-pages` flow below is obsolete
since `build-image.yml` now does the release, manifest, and gh-pages deploy
in-workflow. Kept as an emergency fallback only.

<details>
<summary>Manual fallback (rarely needed)</summary>

```bash
# 1. Generate Imager manifest
./scripts/generate-imager-manifest.sh \
  deploy/pistompOS-3.0.0.img.xz release/3.0.0

# 2. Create GitHub Release (omit --prerelease for production)
gh release create release/3.0.0 \
  deploy/pistompOS-3.0.0.img.xz \
  pistomp-imager-manifest.json \
  --title "pi-Stomp OS 3.0.0" \
  --notes "..."

# 3. Deploy manifest to the right channel + per-version snapshot.
#    Stash the manifest outside the worktree first — `git checkout gh-pages`
#    swaps the tree, so paths from the main branch (pistomp-imager-manifest.json,
#    site/) do not exist once you are on gh-pages.
cp pistomp-imager-manifest.json /tmp/manifest.json
cp site/imager/icon.png /tmp/icon.png

git fetch origin gh-pages
git checkout gh-pages
CHANNEL="stable"   # or "testing" for a -rc/-pre/-beta/-alpha tag
cp /tmp/manifest.json "imager/pistomp-3.0.0.json"
cp /tmp/manifest.json "imager/pistomp-${CHANNEL}.json"
# Legacy URL published in the README — keep it mirroring stable, never delete it.
[ "${CHANNEL}" = "stable" ] && cp /tmp/manifest.json imager/pistomp.json
cp /tmp/icon.png imager/icon.png
git add imager/
git commit -m "deploy imager manifest for 3.0.0 → ${CHANNEL}"
git push origin gh-pages
git checkout main
```

</details>

## CI triggers

| Workflow | Trigger | Produces |
|---|---|---|
| `build-<pkg>.yml` | push to `main` changing `debpkgs/<pkg>/**` | `.deb` GitHub Release (prerelease if version has `~`) |
| `publish-apt-repo.yml` | any release published (and explicit dispatch from `build-deb.yml`) | apt index on `gh-pages` (trixie + trixie-testing) |
| `build-image.yml` | `git push origin release/<version>` or manual dispatch | `.img.xz` + Imager manifest + (if tag) GitHub Release |
| `validate-packages.yml` | `pull_request` | PR status check (add to required checks after first run reveals the exact name — see workflow comment) |
