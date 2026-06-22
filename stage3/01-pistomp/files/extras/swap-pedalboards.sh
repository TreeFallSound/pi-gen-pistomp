#!/usr/bin/env bash
# swap-pedalboards.sh — repoint .pedalboards at a different git remote and resync MOD + pi-stomp.
#
# Usage: swap-pedalboards.sh <git-remote-url> [branch]
#
# Stops pi-stomp, swaps the git tree, clears stale MOD state, restarts mod-ui (forces a fresh
# LILV rescan + bank prune), loads a real new board via REST (rewrites last.json with a
# valid bank id), then starts the pi-stomp service again.
set -euo pipefail

NEW_REMOTE="${1:?usage: swap-pedalboards.sh <git-remote-url> [branch]}"
BRANCH="${2:-}"

PB_DIR="/home/pistomp/data/.pedalboards"
DATA_DIR="/home/pistomp/data"
SETTINGS="$DATA_DIR/config/settings.yml"   # pi-stomp persisted settings (bank lives here)
BACKUP_DIR="$DATA_DIR/.pedalboard-swap-backup"

# Resolve branch: explicit arg wins; otherwise try main, fall back to master.
if [ -z "$BRANCH" ]; then
  for b in main master; do
    if git ls-remote --exit-code --heads "$NEW_REMOTE" "$b" >/dev/null 2>&1; then
      BRANCH="$b"; break
    fi
  done
  [ -z "$BRANCH" ] && { echo "ERROR: neither 'main' nor 'master' found on $NEW_REMOTE"; exit 1; }
  echo "==> Auto-selected branch '$BRANCH'"
fi

echo "==> Backing up current MOD state to $BACKUP_DIR"
mkdir -p "$BACKUP_DIR"
cp -f "$DATA_DIR/last.json"  "$BACKUP_DIR/last.json.bak"  2>/dev/null || true
cp -f "$DATA_DIR/banks.json" "$BACKUP_DIR/banks.json.bak" 2>/dev/null || true
git -C "$PB_DIR" remote get-url origin > "$BACKUP_DIR/origin-remote.bak" 2>/dev/null || true

echo "==> Stopping pi-stomp"
sudo systemctl stop mod-ala-pi-stomp

echo "==> Swapping pedalboard repo -> $NEW_REMOTE ($BRANCH)"
if [ -d "$PB_DIR/.git" ]; then
  git -C "$PB_DIR" remote set-url origin "$NEW_REMOTE"
  git -C "$PB_DIR" fetch origin "$BRANCH"
  git -C "$PB_DIR" reset --hard FETCH_HEAD
  git -C "$PB_DIR" clean -fdx          # drop boards not in the new tree
else
  rm -rf "$PB_DIR"
  git clone --branch "$BRANCH" "$NEW_REMOTE" "$PB_DIR"
fi
chown -R pistomp:pistomp "$PB_DIR"

echo "==> Clearing stale MOD state"
# last.json points at a now-deleted board; remove so mod-ui can't reload a ghost.
rm -f "$DATA_DIR/last.json"
# banks.json references dead absolute paths. If the new repo ships its own banks,
# copy it in; otherwise reset to empty and let MOD/you rebuild banks.
if [ -f "$PB_DIR/banks.json" ]; then
  cp "$PB_DIR/banks.json" "$DATA_DIR/banks.json"
else
  echo "[]" > "$DATA_DIR/banks.json"
fi
chown pistomp:pistomp "$DATA_DIR/banks.json"

# pi-stomp may have a selected bank that no longer exists -> clear it (best-effort)
[ -f "$SETTINGS" ] && sed -i '/^bank:/d' "$SETTINGS" || true

echo "==> Restarting mod-ui"
sudo systemctl restart mod-ui
echo "    waiting for mod-ui webserver..."
until curl -sf http://localhost:80/pedalboard/list >/dev/null 2>&1; do sleep 0.5; done

echo "==> Trigger last.json rewrite with the first pedalboard"
FIRST_PB="$(ls -d "$PB_DIR"/*.pedalboard 2>/dev/null | head -n1)"
if [ -n "$FIRST_PB" ]; then
  curl -fsS -X POST http://localhost:80/pedalboard/load_bundle/ \
    --data-urlencode "bundlepath=$FIRST_PB" >/dev/null
  echo "    loaded $FIRST_PB"
else
  echo "    WARNING: no .pedalboard bundles found in new repo"
fi

echo "==> Starting pi-stomp"
sudo systemctl start mod-ala-pi-stomp
echo "Done. (backup of prior last.json/banks.json/remote in $BACKUP_DIR)"