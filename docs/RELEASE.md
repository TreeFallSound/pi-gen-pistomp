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

## Publish a release manually

```bash
# 1. Generate Imager manifest
./scripts/generate-imager-manifest.sh \
  deploy/pistompOS-3.0.0.img.xz 3.0.0        # writes pistomp-imager-manifest.json

# 2. Create GitHub Release
gh release create v3.0.0 \
  deploy/pistompOS-3.0.0.img.xz \
  pistomp-imager-manifest.json \
  --title "pi-Stomp OS v3.0.0" \
  --notes "..."

# 3. Deploy Imager manifest to gh-pages
git fetch origin gh-pages
git checkout gh-pages
cp ../pistomp-imager-manifest.json imager/pistomp.json
cp ../pistomp-imager-manifest.json "imager/pistomp-3.0.0.json"
cp ../site/imager/icon.svg imager/icon.svg
git add imager/
git commit -m "deploy imager manifest for 3.0.0"
git push origin gh-pages
git checkout main

# 4. Verify in Raspberry Pi Imager
# App Options → Content Repository → Custom URL:
# https://treefallsound.github.io/pi-gen-pistomp/imager/pistomp.json
```

## CI triggers

| Workflow | Trigger | Produces |
|---|---|---|
| `build-<pkg>.yml` | push to `main` changing `debpkgs/<pkg>/**` | `.deb` release |
| `publish-apt-repo.yml` | any release published | apt index on `gh-pages` |
| `build-image.yml` | `git push origin release/<version>` or manual dispatch | `.img.xz` + Imager manifest |
