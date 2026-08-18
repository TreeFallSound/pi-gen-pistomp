# Username coupling: everywhere the user is assumed to be `pistomp`

Exhaustive audit of every place across the three sibling repos where the Linux
**username is assumed/hardcoded to be `pistomp`** (the primary device user).
Produced so the coupling can be made configurable (or defended with a firstboot
guard).

Repos audited:

- `pi-gen-pistomp` — the OS image builder (this repo, a pi-gen fork).
- `pi-stomp` (`../pi-stomp`) — the pi-Stomp application/drivers (Python + shell).
- `pistomp-recovery` (`../pistomp-recovery`) — the recovery/OTA app.

## Forms of the assumption

- **A. Literal `pistomp` as a user/group** — `User=`, `Group=`, `chown pistomp:pistomp`,
  `runuser -u pistomp`, `USER='pistomp'`, `sudo -u pistomp`.
- **B. Hardcoded `/home/pistomp` home paths** — bakes in the username via the home dir.
- **C. Parameterized** via `${FIRST_USER_NAME}` (pi-gen) / `${PISTOMP_USER}` (deploy
  scripts) — still assumes one configured user, but not hardcoded.
- **D. UID/GID `1000`** assumptions — pistomp is assumed to be the first user, uid 1000.

Excluded throughout: `pistomp` as a project/package name (`jack2-pistomp`,
`pistomp-recovery`, `/opt/pistomp`, apt `Origin: pistomp`), image name (`pistompOS`),
hostname/SSID (`pistomp.local`, `pistomp-hotspot`), Python module name, and the paths
`/usr/share/pistomp`, `/etc/pistomp`, `/usr/lib/pistomp`, `/pistomp-cache`.

---

## 1. `pi-gen-pistomp` — source of truth

| File | Line | What |
|---|---|---|
| `config` | 21 | `FIRST_USER_NAME="pistomp"` — **the single source of truth**; default for every `${FIRST_USER_NAME}` below |
| `build.sh` | 214 | `export FIRST_USER_NAME=${FIRST_USER_NAME:-pi}` — upstream fallback (overridden by `config`) |

### 1a. Hardcoded `pistomp` user/group/chown/runuser (A)

| File | Line | What |
|---|---|---|
| `stage2/05-pistomp/files/firstboot.sh` | 110-115 | `chown -R pistomp:pistomp /home/pistomp/.ssh` (+ `/home/pistomp/.ssh` paths) |
| " | 190 | `chown -R pistomp:pistomp /home/pistomp/` |
| " | 195,197,201 | `runuser -u pistomp -- /home/pistomp/pi-stomp/util/{modify_version,pi5_eeprom_update}.sh` |
| `stage2/05-pistomp/files/pistomp-nopasswd.sudoers` | 1-3 | `pistomp ALL=(ALL) NOPASSWD: ALL` |
| `stage2/05-pistomp/files/services/mod-amidithru.service` | 7 | `User=pistomp` |
| `stage2/05-pistomp/files/ps-run` | 3 | `exec sudo … /home/pistomp/pi-stomp/modalapistomp.py` |
| `stage3/01-pistomp/files/extras/swap-pedalboards.sh` | 49,65 | `chown -R pistomp:pistomp "$PB_DIR"`, `chown pistomp:pistomp "$DATA_DIR/banks.json"` |
| `stage2/05-pistomp/02-run.sh` | 59-83 | Build-time validator greps `^User=pistomp` across installed units (asserts against the literal `pistomp` user) |
| `stage2/05-pistomp/files/services/rpi-preseed-before-pistomp.conf` | 7,13,16-17 | Comments documenting the `User=pistomp` invariant |

### 1b. Hardcoded `/home/pistomp` home paths (B)

- `stage2/05-pistomp/files/services/ttymidi.service:7-8` — `Environment=HOME=/home/pistomp`, `WorkingDirectory=/home/pistomp`
- `stage3/01-pistomp/01-run.sh:220` — writes `/home/pistomp/.osbuild` (hardcoded even though the rest of the script is parameterized)
- `stage3/01-pistomp/files/banks.json:6,10,14,23,27,31,35` — pedalboard bundle paths `/home/pistomp/data/.pedalboards/…`
- `stage3/01-pistomp/files/display-pistomp-logo:32` — `OSBUILD="/home/pistomp/.osbuild"`
- `stage3/01-pistomp/files/extras/expression-pedal.sh:7` — `/home/pistomp/data/config/default_config.yml`
- `stage3/01-pistomp/files/extras/more-user-files.sh:5` — `/home/pistomp/data/user-files`
- `stage3/01-pistomp/files/extras/swap-pedalboards.sh:14-15` — `/home/pistomp/data{,/.pedalboards}`

### 1c. Parameterized `${FIRST_USER_NAME}` (C)

`stage1/01-sys-tweaks/00-run.sh` (8-14, creates the user), `stage2/01-sys-tweaks/01-run.sh`
(17-20, 54), `stage2/02-net-tweaks/*`, `stage2/05-pistomp/01-run.sh` (75, 119-120),
`02-run.sh` (40), `03-run.sh` (7-8,13,64,124), `04-run.sh` (8,
`chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME}`), `stage3/01-pistomp/01-run.sh`
(15,27-28,38,42-55,84-93,139-147), `export-image/01-user-rename/01-run.sh:5`
(`SUDO_USER="${FIRST_USER_NAME}" rename-user`), `export-image/05-finalise/01-run.sh:36-37`.

### 1d. UID/GID 1000 assumptions (D)

- `stage2/01-sys-tweaks/01-run.sh:17-20` — `install -o 1000 -g 1000 …`, `chown 1000:1000 …/.ssh/authorized_keys`

---

## 2. `pi-gen-pistomp/debpkgs/**` — hardcoded package files

**User/Group (A):**

- `browsepy/debian/browsepy.browsepy.service:11-12` — `User=pistomp`, `Group=pistomp`
- `jackbridge/debian/jackbridge.pi-stomp-jackbridge.service:11` — `User=pistomp` (Group is `audio`)
- `mod-host-pistomp/debian/mod-host-pistomp.mod-host.service:10-11` — `User=pistomp`, `Group=pistomp`
- `mod-ui/debian/mod-ui.mod-ui.service:45-46` — `User=pistomp`, `Group=pistomp`
- `pi-stomp/debian/pi-stomp.mod-ala-pi-stomp.service:11` — `User=pistomp`
- `pistomp-recovery/debian/pistomp-recovery.pistomp-recovery.service:8-9` — `User=pistomp`, `Group=pistomp`

**chown (A):**

- `mod-ui/debian/postinst:12-13`, `pi-stomp/debian/postinst:19-21`, `pistomp-recovery/debian/postinst:10` — `chown -R pistomp:pistomp …`

**Home paths (B):**

- `browsepy.service:9-10` (`WorkingDirectory`/`ExecStart` under `/home/pistomp/data/user-files`), `browsepy/debian/control:13`
- `cabsim-lv2/debian/postinst:6-7`, `veja-1960-cab-lv2/debian/postinst:6-7`, `veja-bass-cab-lv2/debian/postinst:6-7` — `/home/pistomp/.lv2/…`
- `mod-host-pistomp.mod-host.service:12` — `LV2_PATH=/home/pistomp/.lv2…`
- `mod-ui.mod-ui.service:15-31` — `HOME`, `LV2_PATH`, `LV2_PLUGIN_DIR`, `LV2_PEDALBOARDS_DIR`, `MOD_DATA_DIR`, `MOD_USER_PEDALBOARDS_DIR`, `MOD_USER_FILES_DIR`, `MOD_KEYS_PATH` — all under `/home/pistomp/data`
- `pi-stomp.mod-ala-pi-stomp.service:12` — `WorkingDirectory=/home/pistomp`
- `pi-stomp/debian/{control:18,postinst:7}` — `/home/pistomp/pi-stomp` symlink target
- `pistomp-recovery.pistomp-recovery.service:10` — `WorkingDirectory=/home/pistomp`

**UID/GID 1000 (D):**

- `pistomp-usb-automount/files/pistomp-usb-mount:29` — `mount … uid=1000,gid=1000 …` (assumes pistomp is uid/gid 1000)

*(Note: `jack2-pistomp/debian/extra/jack.service` uses `User=jack`/`Group=jack` — not pistomp, excluded.)*

---

## 3. `pi-stomp` — application code

**Python (A):**

- `pistomp/settings.py:25` — `USER = 'pistomp'`; line 64 `shutil.chown(self.file, user=USER, group=USER)`
- `pistomp/relay.py:67` — `shutil.chown(f, user="pistomp", group=None)`
- `modalapi/modhandler.py:157` — `self.username = "pistomp"`; consumed at `1685` and `1741` (`subprocess.check_output(["sudo", "-u", self.username, cmd])`)

**Python home paths (B):**

- `pistomp/settings.py:23` — `DATA_DIR = '/home/pistomp/data/config'`
- `pistomp/config.py:26` — `data_dir = '/home/pistomp/data/config'`
- `modalapi/modhandler.py:148` — `data_dir="/home/pistomp/data"` default arg; `162` — `self.build_file = "/home/pistomp/.osbuild"`

**Shell / deploy (B + C):**

- `deploy.sh:25` — `USER="${PISTOMP_USER:-pistomp}"` (C); `27` — `REMOTE_DIR="/home/pistomp/pi-stomp"` (B)
- `util/data-backup.sh:20`, `util/data-restore.sh:20` — `/home/pistomp/data`
- `util/modify_version.sh:30` — `/home/pistomp/.pedalboards`
- `util/update-menu.sh:25-26,32` — `/home/pistomp/{.pedalboards,data/.lv2,pi-stomp/…}`
- `util/update-sample-pedalboards.sh:21` — `/home/pistomp/.pedalboards`

**Docs / tests (B):**

- `GUIDE.md:80`, `docs/architecture.md:149,221,276,419-423,483`, `docs/session-recording-plan.md:4,134`
- `tests/test_ws_protocol.py:407,413`, `tests/v3/test_nam_panel.py:58,66`, `tests/v3/test_plugin_extra_data.py:63-64` — `/home/pistomp/data/user-files/…` fixtures

---

## 4. `pistomp-recovery`

- `src/pistomp_recovery/constants.py:4` — `PISTOMP_USER: str = "pistomp"` (A)
- `src/pistomp_recovery/constants.py:5` — `PISTOMP_HOME: str = "/home/pistomp"` (B) — **derives** `DATA_DIR`, `CONFIG_DIR`, `PEDALBOARDS_DIR`, `RECOVERY_DIR`, `PACKAGES_STAMP_FILE`, `PLUGINS_STAMP_FILE` (lines 12-30)
- `deploy.sh:7` — `USER="${PISTOMP_USER:-pistomp}"` (C); `6` host default `pistomp.local`
- `CLAUDE.md:34-36,47` — docs default `pistomp@pistomp.local` and `/home/pistomp/…` paths

*(Excluded: `git_util.py:37-38,50-52` sets git author `recovery@pistomp.local` / `pistomp-recovery`
— commit identity metadata, not the OS user. The recovery service unit lives in
`pi-gen-pistomp/debpkgs/pistomp-recovery` and is listed in §2.)*

---

## Summary of the coupling

The username `pistomp` is assumed in ~90 locations across the three repos. The couplings
that would actually break if the user were renamed (as opposed to docs/tests):

1. **`pi-gen-pistomp/config:21`** — the origin. Stage scripts mostly honor
   `${FIRST_USER_NAME}`, but `firstboot.sh`, `banks.json`, `.osbuild` writes, the extras
   scripts, the sudoers file, and `mod-amidithru.service` hardcode `pistomp` and would
   **not** follow a change to `FIRST_USER_NAME`.
2. **All `debpkgs/**` service units + postinst chowns** — fully hardcoded; packages are
   built independently of `FIRST_USER_NAME`.
3. **`pi-stomp` runtime** — `settings.py`/`relay.py`/`modhandler.py` hardcode both the user
   (for `chown`/`sudo -u`) and `/home/pistomp` data paths.
4. **`pistomp-recovery/constants.py`** — cleanly centralized in two constants; easiest to
   make configurable.
5. **UID/GID 1000 assumptions** — `pistomp-usb-automount` and `stage2/01-sys-tweaks` assume
   pistomp == uid 1000.

If the goal is to make the username configurable, the hardcoded literals in §1a/1b, §2,
§3-Python, and the two constants in §4 are the real work; the `${FIRST_USER_NAME}` /
`${PISTOMP_USER}` sites in §1c and the deploy scripts already parameterize it.
