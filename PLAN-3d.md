# PLAN-3d: Python Component Packaging — pi-stomp and mod-ui

Debate document for how to package pi-stomp and mod-ui as `.deb` files
while preserving developer workflows and enabling OTA upgrades via
pistomp-recovery.

---

## 1. Findings

### 1.1 What deploy.sh does

`../pi-stomp/deploy.sh` is a laptop-side script that SCPs Python source
files from the developer's working copy to the device:

```bash
scp modalapistomp.py pistomp@pistomp.local:/home/pistomp/pi-stomp/
scp modalapi/*.py   pistomp@pistomp.local:/home/pistomp/pi-stomp/modalapi/
scp pistomp/*.py    pistomp@pistomp.local:/home/pistomp/pi-stomp/pistomp/
scp -r blend common fonts images ui uilib util \
    pistomp@pistomp.local:/home/pistomp/pi-stomp/
```

Then it restarts `mod-ala-pi-stomp` and tails the journal. It is hardcoded
to the path `/home/pistomp/pi-stomp/` on every scp line. There is no flag,
no env var, no indirection. The service name it restarts is
`mod-ala-pi-stomp`.

### 1.2 Service file paths

`stage2/05-pistomp/files/services/mod-ala-pi-stomp.service`:
```
ExecStart=/opt/pistomp/venvs/pi-stomp/bin/python /home/pistomp/pi-stomp/modalapistomp.py
```

Two paths hardcoded here:
- venv: `/opt/pistomp/venvs/pi-stomp/`
- source entry point: `/home/pistomp/pi-stomp/modalapistomp.py`

`stage2/05-pistomp/files/services/mod-ui.service`:
```
Environment=MOD_HTML_DIR=/opt/mod-ui-venv/share/mod/html
ExecStart=/usr/bin/authbind /opt/mod-ui-venv/bin/mod-ui
```

Currently the pi-gen build puts mod-ui at `/opt/mod-ui-venv/`. There is no
separate source directory — everything (venv, HTML assets, Python package)
lives inside the venv tree.

### 1.3 Stage 3 installs pi-stomp as a git clone

`stage3/01-pistomp/01-run.sh` clones `TreeFallSound/pi-stomp` branch
`pistomp-v3` to `/home/pistomp/pi-stomp`. It then creates a uv venv at
`/opt/pistomp/venvs/pi-stomp` with `--system-site-packages`. The venv is
populated in `02-run.sh` by `uv sync`. The source tree at
`/home/pistomp/pi-stomp` is the live working directory for the service.

### 1.4 What pistomp-arch does

The Arch PKGBUILD for pi-stomp:
- Clones the repo and builds a relocatable venv at `$srcdir/venv`.
- Installs the venv to `/opt/pistomp/venvs/pi-stomp/`.
- Installs the full source tree to `/opt/pistomp/pi-stomp/` (package-owned).
- mod-ala-pi-stomp.service starts:
  `/opt/pistomp/venvs/pi-stomp/bin/python /opt/pistomp/pi-stomp/modalapistomp.py`

The Arch PKGBUILD for mod-ui:
- Builds a relocatable 3.11 venv at `/opt/pistomp/venvs/mod-ui/`.
- Installs source assets to `/opt/pistomp/mod-ui/` (html/, default.pedalboard).
- mod-ui.service uses `MOD_HTML_DIR=/opt/pistomp/mod-ui/html` and
  `ExecStart=/opt/pistomp/venvs/mod-ui/bin/mod-ui`.

Key insight: **pistomp-arch deliberately moves pi-stomp out of `/home/pistomp`
into `/opt/pistomp/pi-stomp/`**. The source tree is package-owned, not a user
git checkout. `deploy-pkg.sh` replaces `deploy.sh` entirely — it rsyncs the
local source tree to the device, runs `makepkg` there, and installs the
resulting `.pkg.tar.zst`.

### 1.5 What pistomp-recovery expects

`pistomp-recovery/src/pistomp_recovery/constants.py` lists the tracked
packages:

```python
PISTOMP_PACKAGES: tuple[str, ...] = (
    ...
    "pi-stomp",
    "mod-ui",
    "pistomp-recovery",
)
```

It calls `apt-get install -y <package>` (via `AptManager`) and
`pacman -S <package>` (via `PacmanManager`). It tracks versions via
`dpkg-query` or `pacman -Q`. It rolls back by calling
`manager.install_version(name, version)`.

`PISTOMP_PACKAGES_DEBIAN: tuple[str, ...] = PISTOMP_PACKAGES` — the comment
reads "Adjust here once the .deb names are finalised", confirming the Debian
package names are expected to mirror the Arch names: `pi-stomp` and `mod-ui`.

`PACKAGE_SERVICES` maps:
- `"pi-stomp"` → restarts `["mod-ala-pi-stomp"]`
- `"mod-ui"` → restarts `["mod-ui"]`

pistomp-recovery does not parse or hardcode any file paths. It only needs
both components to be installable and queryable by name via the system package
manager.

### 1.6 Path divergence: pi-gen vs pistomp-arch

| Item | Current pi-gen | pistomp-arch target |
| :--- | :--- | :--- |
| pi-stomp source | `/home/pistomp/pi-stomp/` | `/opt/pistomp/pi-stomp/` |
| pi-stomp venv | `/opt/pistomp/venvs/pi-stomp/` | `/opt/pistomp/venvs/pi-stomp/` |
| mod-ui venv | `/opt/mod-ui-venv/` | `/opt/pistomp/venvs/mod-ui/` |
| mod-ui html assets | inside venv `share/mod/html` | `/opt/pistomp/mod-ui/html` |
| deploy.sh target path | `/home/pistomp/pi-stomp/` | `/opt/pistomp/pi-stomp/` |

---

## 2. End-user UX analysis

**What packaging as `.deb` gives users:**

- `pistomp-recovery` can offer "Check for updates" and install `pi-stomp` and
  `mod-ui` via `apt-get install pi-stomp` without reflashing.
- Rollback works: `install_version("pi-stomp", stamped_version)` calls
  `apt-get install pi-stomp=<version>` with the old version pinned.
- Clean uninstall: `dpkg` tracks every file the package installed.
- `apt upgrade` gives users a one-command update path when new releases land
  in the custom apt repo.
- Factory reset is coherent: pistomp-recovery can restore the factory-stamped
  version of any package.

This is the primary motivation. Users cannot practically run `makepkg` on
device; apt is the only viable OTA path on Debian.

---

## 3. Developer UX analysis

**What full `.deb` packaging costs developers:**

The pi-gen stage3 script currently clones pi-stomp directly to
`/home/pistomp/pi-stomp/` — there is no symlink. The running pistomp-arch
device has `/home/pistomp/pi-stomp -> /opt/pistomp/pi-stomp` as a symlink
created by the pistomp-arch PKGBUILD's postinst. Pi-gen does not create this
symlink today.

**The symlink is the resolution.** If the pi-stomp `.deb` installs to
`/opt/pistomp/pi-stomp/` and its `postinst` creates:
```bash
ln -sf /opt/pistomp/pi-stomp /home/pistomp/pi-stomp
```
then deploy.sh continues to work on pi-gen images unchanged — it syncs to
`/home/pistomp/pi-stomp/` which resolves to the deb-managed path. This is
exactly what pistomp-arch already does. No path changes needed in deploy.sh,
no changes needed in service files (they already reference
`/home/pistomp/pi-stomp/modalapistomp.py` which resolves through the symlink).

The venv is separate from the source. deploy.sh never touches the venv — it
only SCPs `.py` files. So the venv path (`/opt/pistomp/venvs/pi-stomp/`) is
not a problem for deploy.sh.

**What packaging preserves:**
- Hot-restarting the service after deploy.sh still works, because
  `systemctl restart mod-ala-pi-stomp` is the last step and the service's
  `ExecStart` points at a Python script, not a compiled binary.
- `uv pip install` or `uv add` in the venv still works — the venv is not
  wiped by source-tree updates.

**mod-ui developer workflow:**
mod-ui HTML/JS template hot-patching requires write access to
`MOD_HTML_DIR`. On the current pi-gen build that is inside the venv
(`/opt/mod-ui-venv/share/mod/html`). A `.deb` that puts html at
`/opt/pistomp/mod-ui/html` (matching pistomp-arch) would make this easier,
not harder, since `/opt/pistomp/mod-ui/` is a plain directory, not buried
inside a venv tree.

---

## 4. Options

### Option A — Full .deb, move pi-stomp to /opt/pistomp/pi-stomp/

Package pi-stomp and mod-ui exactly as pistomp-arch does. The `.deb` installs:
- `/opt/pistomp/pi-stomp/` — source tree (package-owned)
- `/opt/pistomp/venvs/pi-stomp/` — uv venv (built with `--copies`; shebangs patched in postinst)
- `/opt/pistomp/venvs/mod-ui/` — 3.11 venv (same approach)
- `/opt/pistomp/mod-ui/html` — html assets

Update `mod-ala-pi-stomp.service` ExecStart to
`/opt/pistomp/venvs/pi-stomp/bin/python /opt/pistomp/pi-stomp/modalapistomp.py`.

The `.deb` `postinst` creates `ln -sf /opt/pistomp/pi-stomp /home/pistomp/pi-stomp`.
deploy.sh targets `/home/pistomp/pi-stomp/` which resolves through the symlink —
**zero changes needed in deploy.sh**.

**Pros:**
- Full OTA via `apt upgrade`. pistomp-recovery works as designed.
- Path parity with pistomp-arch.
- `apt upgrade` does not touch `/home/pistomp/` at all.
- `/opt/pistomp/` is a conventional location for application files; makes
  the installation layout coherent.

**Cons:**
- deploy.sh requires zero changes (symlink in postinst handles path resolution).
- `/opt/` is package-managed, so any direct file edits are "dirty" from
  dpkg's perspective. `apt upgrade` will clobber them. But: dpkg's conffile
  mechanism only protects `/etc/`; for `/opt/` there is no protection.
- Developer iterating fast via deploy.sh needs to accept that `apt upgrade`
  will overwrite their changes. Acceptable if upgrade is a deliberate act.

**Verdict on deploy.sh coexistence:** Compatible unchanged. The `postinst`
symlink `/home/pistomp/pi-stomp -> /opt/pistomp/pi-stomp` means deploy.sh
resolves to the correct path without modification. Files written by deploy.sh
will be overwritten by the next `apt upgrade pi-stomp`, which is expected
(upgrade replaces old code).

---

### Option B — Partial packaging: .deb for mod-ui, git clone for pi-stomp

Package mod-ui as a `.deb` (it is rarely hot-patched and requires a compiled
C extension `libmod_utils.so`). Keep pi-stomp as a git clone at
`/home/pistomp/pi-stomp/` managed by stage3, with the venv at
`/opt/pistomp/venvs/pi-stomp/`.

For OTA upgrades of pi-stomp, pistomp-recovery would call `git pull` in the
clone and `uv sync` instead of `apt-get install`. This requires a custom
pistomp-recovery backend path for pi-stomp.

**Pros:**
- deploy.sh requires zero changes.
- pi-stomp stays in `/home/pistomp/pi-stomp/` exactly as today.
- Developer iteration is frictionless.

**Cons:**
- pistomp-recovery already tracks `pi-stomp` in `PISTOMP_PACKAGES` and calls
  `manager.install()` on it. A git-based path requires forking the package
  management logic in pistomp-recovery specifically for pi-stomp.
- No version pinning, no atomic rollback for pi-stomp. Rolling back means
  `git checkout <sha>` and `uv sync` — fragile across Python dep changes.
- `apt list --upgradeable` will never report pi-stomp. The update UI in
  pistomp-recovery shows nothing for it until special-cased.
- Two different update mechanisms in one system creates operational confusion.
- Does not scale: if pi-stomp is special-cased, every future "too awkward to
  package" component gets its own special case.

---

### Option C — .deb with developer-mode flag

Full `.deb` as in Option A, but add a flag file `/etc/pistomp/dev-mode` that
service scripts check. When the flag exists, `mod-ala-pi-stomp.service` uses
`/home/pistomp/pi-stomp/modalapistomp.py` instead of the installed path.

pistomp-arch does not implement anything like this. The PKGBUILD comment
explicitly notes "deploy-pkg.sh --source" as the developer workflow, not
in-place editing.

**Pros:**
- deploy.sh continues targeting `/home/pistomp/pi-stomp/` unchanged.
- OTA upgrade installs cleanly to `/opt/pistomp/pi-stomp/` without touching
  the dev path.

**Cons:**
- Two code paths in the service file. Bugs that only manifest in one mode are
  possible and hard to diagnose.
- The dev path at `/home/pistomp/pi-stomp/` must be kept in sync with the
  venv. On a fresh image without dev-mode the clone does not exist; tooling
  must set it up.
- Adds complexity to service files for a use case that deploy-pkg.sh already
  solves more cleanly on Arch.
- pistomp-recovery has no knowledge of dev-mode. Upgrades via recovery would
  update `/opt/` but not affect the running dev path.

---

## 5. Recommendation

**Choose Option A (full .deb, move pi-stomp to /opt/pistomp/pi-stomp/).**

The blockers for Option A are all minor:

1. **deploy.sh** — zero changes needed. The `postinst` creates
   `ln -sf /opt/pistomp/pi-stomp /home/pistomp/pi-stomp`; deploy.sh's scp
   targets resolve through the symlink unchanged.

2. **Service file** — update `mod-ala-pi-stomp.service` ExecStart to
   `/opt/pistomp/venvs/pi-stomp/bin/python /opt/pistomp/pi-stomp/modalapistomp.py`.

3. **Stage3 run script** — replace the `git clone ... /home/pistomp/pi-stomp`
   block with `apt-get install -y pi-stomp` installed from `cache/` (same
   pattern as C packages in PLAN-3c — **no GitHub Pages apt repo required at
   image build time**). Remove the `uv sync` step; the venv is built inside
   the `.deb` build process.

4. **`systemctl enable` in chroot** — `systemctl enable` fails with no running
   systemd. Use `dh_installsystemd` in `debian/rules`, which generates
   `postinst` code using `deb-systemd-helper enable` — this creates the
   correct symlinks in `/etc/systemd/system/` without needing systemd running.
   Remove the existing `ln -sf mod-ala-pi-stomp.service` from `stage3/01-run.sh`
   to avoid conflict.

5. **uv venv relocatability** — `uv venv --relocatable` is not a real flag.
   Use `uv venv --copies` (copies files instead of symlinks so the venv
   survives being moved) and patch shebangs in `postinst`:
   ```bash
   find /opt/pistomp/venvs/pi-stomp/bin -type f \
       -exec sed -i "1s|^#!.*python.*|#!/opt/pistomp/venvs/pi-stomp/bin/python|" {} \;
   ```

6. **`default.pedalboard`** — user data; must NOT be written by `postinst`
   (upgrades would clobber user-modified pedalboards). The `.deb` ships it
   under `/usr/share/pistomp/default.pedalboard/`. Stage3 copies it to
   `/home/pistomp/data/.pedalboards/` once at image build time. Firstboot
   handles fresh devices (same as today).

7. **mod-ui service** — update `MOD_HTML_DIR` from
   `/opt/mod-ui-venv/share/mod/html` to `/opt/pistomp/mod-ui/html` and
   `ExecStart` from `/opt/mod-ui-venv/bin/mod-ui` to
   `/opt/pistomp/venvs/mod-ui/bin/mod-ui`.

The developer workflow concern is real but manageable. deploy.sh overwrites
files at the installed path, which `apt upgrade` will later overwrite back.
That is the correct semantic: deploy.sh is for "try this before packaging",
not for permanent local state.

The gain — pistomp-recovery can upgrade, rollback, and factory-reset
`pi-stomp` and `mod-ui` atomically via apt, with full version tracking — is
substantial and cannot be achieved with Options B or C without bespoke
complexity.

**Summary of changes required:**

| File | Change |
| :--- | :--- |
| `../pi-stomp/deploy.sh` | No changes — symlink handles path resolution |
| `stage2/…/services/mod-ala-pi-stomp.service` | ExecStart: `/home/pistomp/pi-stomp/` → `/opt/pistomp/pi-stomp/` |
| `stage2/…/services/mod-ui.service` | ExecStart + MOD_HTML_DIR: `/opt/mod-ui-venv/` → `/opt/pistomp/venvs/mod-ui/` and `/opt/pistomp/mod-ui/html` |
| `stage3/01-pistomp/01-run.sh` | Replace git clone + uv venv block with `apt-get install pi-stomp` from `cache/` |
| `stage2/05-pistomp/02-run.sh` | Replace mod-ui source build block with `apt-get install mod-ui` from `cache/` |
| `stage3/01-pistomp/01-run.sh` | Remove `ln -sf mod-ala-pi-stomp.service` (moved to deb postinst) |
| `debpkgs/pi-stomp/debian/rules` | Use `dh_installsystemd` for service enablement |
