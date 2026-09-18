# Seed ALSA card state before JACK

## Problem

pi-Stomp supports three audio cards:

- IQaudIO CODEC (`IQaudIOCODEC`)
- HiFiBerry (`sndrpihifiberry`)
- AudioInjector (`audioinjectorpi`)

The image enables `dtoverlay=iqaudio-codec` in
`stage2/05-pistomp/files/config.txt`. The user selects another overlay in the
recovery Audio Card menu, which calls `../pi-stomp/util/change-audio-card.sh`.

The pi-Stomp application owns the card-specific ALSA restore. It runs
`Audiocard.restore()` from `modalapistomp.py` after startup. The application
service starts after JACK, mod-host, and mod-ui. Thus the application cannot
restore a card state when JACK cannot open the ALSA stream.

The failure sequence:

1. The Audio Card operation removes `/var/lib/alsa/asound.state`.
2. `alsa-restore` loads no card-specific fallback.
3. JACK starts before pi-Stomp.
4. The codec stays at its hardware defaults.
5. The playback DAPM path stays inactive.
6. The I2S clock and the DMA transfer do not progress.
7. JACK fails its ALSA stream.
8. mod-host and mod-ui do not reach their normal state.
9. pi-Stomp does not run `Audiocard.restore()`.

The DA7213 driver shows that the hardware defaults are not a complete
playback configuration
(`/tmp/kernel-src/linux-.../sound/soc/codecs/da7213.c`):

- `DA7213_DAI_CLK_MODE` defaults to `0x01`; the DAI clock-enable bit is clear.
- `DA7213_DAI_CTRL` defaults to `0x08`; the DAI-enable bit is clear.
- `DA7213_MIXOUT_L_SELECT` and `DA7213_MIXOUT_R_SELECT` default to `0x00`;
  the DAC-to-mixout route bits are clear.

The pi-Stomp IQaudIO fallback state enables the required playback controls,
including `Headphone Switch` and both DAC-to-mixout switches.

Observed on the failing device:

```text
Headphone                 off
Mixout Left DAC Left      off
Mixout Right DAC Right    off
BCLK                      low
LRCLK                     low
DMA                        dma2chan4 failed to stop
ALSA                       EIO during playback
JACK                       ALSA poll timeout
```

Installing the known-good IQaudIO state before JACK restored the full service
chain. This is direct evidence of a pre-JACK ALSA configuration failure.

## Decision

Ship the three known-good state files in `pistomp-audio` and seed
`/var/lib/alsa/asound.state` at the moments a component knows the card:

1. `firstboot.sh` seeds the state for the card enabled in `config.txt` and
   restores it.
2. The recovery Audio Card menu and the Factory Reset path seed the state for
   the selected card instead of deleting it.
3. For everything else, the JACK crash screen is the safety net: JACK failure
   already routes to `pistomp-recovery.service` through `OnFailure=`, and the
   same Audio Card menu re-seeds and reboots.

**No seeder detects cards.** The enabled `dtoverlay=` line is the single
source of truth: enumeration can only confirm what the overlay declares, and
when the overlay is wrong, the intended card does not exist for detection to
find. Every seeder resolves the overlay name through the mapping below.

pi-Stomp keeps runtime mixer control and the debounced `alsactl store`
persistence. All fallback-restore code moves out of the application.

### Why no boot-time service is needed

- Stock `alsa-utils` restores every card it knows about: the udev rule
  `90-alsa-restore.rules` runs `alsactl restore` on each `controlC*` add
  (hotplugged USB cards included), and `alsa-restore.service` restores at
  boot and stores at shutdown. Both are `-`-prefixed, so a missing state
  file is not an error. Restore is upstream behavior; only seeding was
  missing.
- Every user-triggered case seeds before the affected boot.
- The remaining cases — incompatible user mixer state, a state written for a
  different card, state loss — fail one boot into the crash screen, where one
  menu action repairs them. Accepted trade: rare, recoverable, manual.

### Overlay selection is unchanged

The menu keeps both functions: select the next-boot `dtoverlay=` line, and
seed the matching state. The overlay cannot change after boot, so the menu
stays the only selection mechanism until automatic pre-boot HAT detection
exists.

We use the `dtoverlay` string as the audio-card key: recovery's
`AUDIO_CARD_OVERLAYS`, `active_card`, the menu selection, the wrapper
script, `seed.sh`, and firstboot all pass it unchanged. Nothing translates
to an ALSA card ID. Keep the three lists in step: `constants.py`,
`change-audio-card.sh`, `seed.sh`, and the image's `config.txt`.

## Card mapping

| Overlay | ALSA card ID | State file |
|:---|:---|:---|
| `iqaudio-codec` | `IQaudIOCODEC` | `iqaudiocodec.state` |
| `hifiberry-dacplusadc` | `sndrpihifiberry` | `hifiberry.state` |
| `audioinjector-wm8731-audio` | `audioinjectorpi` | `audioinjector.state` |

## Package layout

`pistomp-audio` ships:

```text
/usr/lib/pistomp/alsa/iqaudiocodec.state
/usr/lib/pistomp/alsa/hifiberry.state
/usr/lib/pistomp/alsa/audioinjector.state
/usr/lib/pistomp/alsa/seed.sh
```

`seed.sh <overlay>` resolves the overlay through the mapping table and copies
the matching state to `/var/lib/alsa/asound.state`. The whole file is
written: sections for other cards are clobbered. (Seeds are rare — first
boot, card switch, factory reset. The next `alsactl store` snapshots every
card, so dropped sections regenerate at the first clean shutdown or the
next mixer change. USB mixer settings survive normal reboots; they are
lost only at a seed. The one non-obvious case: re-arming firstboot —
delete `/boot/firmware/firstboot.done` and reboot, as `pistomp.conf`
documents — re-seeds and drops them.)

## Dependencies

`pistomp-recovery` declares `Depends: pistomp-audio (>= 1.1.0-1)`: the Factory
Reset seed and the Audio Card menu invoke `seed.sh` at runtime. The pinned
version is the release that ships `seed.sh` and the state files.

`pi-stomp` declares `Depends: pistomp-audio (>= 1.1.0-1)`: it keeps
`util/change-audio-card.sh` as a wrapper that calls `seed.sh` — the
documented manual card-switch path — and the dependency guarantees the
script it forwards to exists. No recovery pin: released recovery has no
Audio Card menu, so no recovery release ever invoked the wrapper, and the
menu rework and the wrapper change can ship in either order.

Recovery's emulated backend serves the same files under its fake root.

## Seeders

### firstboot

`stage2/05-pistomp/files/firstboot.sh`, in the audio-configuration section:

1. Read the enabled `dtoverlay=` audio-card line from
   `/boot/firmware/config.txt` — the same overlays `audio_card.active_card`
   recognizes.
2. `seed.sh <overlay>` writes the state.
3. Run `alsactl --no-ucm restore -f /var/lib/alsa/asound.state`.

Step 3 is required: udev and `alsa-restore.service` run before
`firstboot.service`, so nothing else restores the state seeded in step 2.
`jack.service` is `After=firstboot.service`, so JACK then opens a configured
card.

### Recovery Audio Card menu

The real backend rewrites `config.txt` with recovery's own
`audio_card.select_card` (as the emulated backend already does) and calls
`seed.sh` for the selected overlay. After the reboot, the stock udev rule
restores the seeded state.

### Recovery Factory Reset

`BootFacet._seed_alsa_state` writes the state for the fitted card instead of
deleting the file. The fitted card comes from the same
`audio_card.active_card` read the `config.txt` merge uses, with the same
never-guess policy: when the selection is absent or ambiguous, leave the
state file alone rather than seed a state that matches no card.

### The crash-screen path

No code. When JACK fails, `OnFailure=pistomp-recovery.service` opens
recovery on the LCD. The user opens Audio: \<card\>, selects the fitted
card, which seeds the state, and reboots. The menu must stay reachable from
the crash screen.

## Migration plan

The order is fixed. Each release ships before the next:

1. **`pistomp-audio` 1.1.0-1** — add the state files and `seed.sh`; bump the
   changelog. OTA delivers it before any caller exists. No risk: the
   payload is inert data and an uninvoked script.
2. **`pistomp-recovery` 0.1.0-33** — add the Audio Card menu
   (`audio_card.select_card` + `seed.sh`, no sudo callout), change Factory
   Reset from delete to seed, declare `Depends: pistomp-audio (>= 1.1.0-1)`.
3. **`pi-stomp`** — remove `audiocard.restore()` and the `restore()` method
   from `modalapistomp.py`, remove `setup/audio/*.state`, rewrite
   `util/change-audio-card.sh` as a wrapper around `seed.sh`, declare
   `Depends: pistomp-audio (>= 1.1.0-1)`. Steps 2 and 3 are independent:
   released recovery never invoked the script (it has no Audio Card
   menu), so either order ships.
4. **Image** — add the firstboot seed and restore to
   `stage2/05-pistomp/files/firstboot.sh`, rebuild, release. Ships last:
   the build resolves the three updated packages from the apt suites, so
   the firstboot change lands in the image that carries them.

The script is kept as a wrapper, not deleted: the documented manual
card-switch path (SSH, `util/change-audio-card.sh`) keeps working, now
seeding via `seed.sh`.

## Verification requirements

### Fresh-state boot

- Remove the global ALSA state; boot each supported overlay.
- Confirm firstboot seeds and restores the matching state.
- Confirm JACK, mod-host, mod-ui, and pi-stomp start without the crash
  screen.

### Card switch

- Switch cards through the menu for each pair of overlays.
- Confirm the state file on disk is the selected card's.
- Confirm the next boot restores the new card and starts the service chain.

### Existing-state boot

- Modify a harmless mixer value; store; reboot.
- Confirm the normal boot preserves the user state (nothing re-seeds).

### Incompatible-state boot

- Disable a required playback route; store; reboot.
- Confirm the boot lands on the crash screen.
- Confirm the Audio Card menu re-seeds and the next boot starts the chain.

### Factory Reset

- Factory Reset with each card fitted.
- Confirm the seeded state matches the fitted card and the next boot starts
  the chain without the crash screen.

### Card mismatch / moved SD

- Boot a state written for a different supported card (e.g. move the SD
  between two fitted devices).
- Confirm the boot lands on the crash screen and the menu recovers it.

### USB JACK device

- Set `JACK_DEVICE` to a USB card.
- Confirm the HAT is seeded and restored, JACK starts on the USB card, and
  no path fails on the unsupported card ID.

## Acceptance criteria

The change is complete when:

- A missing global state never causes a JACK failure on first boot, card
  switch, or factory reset.
- Every seed is chosen from the overlay enabled in `config.txt` (or the
  user's menu selection); no seeder reads `/proc/asound` to decide.
- A matching user state stays authoritative on normal boots.
- Factory Reset leaves a bootable state seeded for the fitted card.
- A mixer-state JACK failure lands on the crash screen, where the Audio Card
  menu repairs it.
- pi-Stomp no longer seeds audio state: `restore()` and `setup/audio/` are
  gone, and `change-audio-card.sh` only forwards to `seed.sh`.
- Overlay selection remains available in recovery.
- `JACK_DEVICE` pointed at a USB card works unchanged.
- `pistomp-recovery` and `pi-stomp` declare the pinned `Depends:` versions
  above.