# The silent card

A field study of a race condition that is twelve years old, told from the
stage outwards.

Status: **diagnosed, reproduced on demand, repaired in userspace, not yet fixed upstream**
Hardware: Raspberry Pi 3 Model A Plus, IQaudio CODEC (DA7213)
Kernel: `6.18.36-rpi-v8-rt`, from `raspberrypi/linux` commit `954341c412dd`

---

## 1. The subject in the field

Observe a musician. They buy a pi-Stomp, and they write the image to an SD
card, and they put the card in the pedal. They connect a guitar, and they
connect an amplifier, and they apply power. This is the first boot of that
card, and it is the only first boot that card will ever have.

The screen lights up. The splash artwork appears, and the boot messages
move, and then nothing more happens. There is no sound. The musician waits,
because the first boot is documented as slow. The musician waits longer.

The musician now does what every musician does. They power the pedal off,
and they power it on again. **The pedal works.** The sound returns, the
screen fills, and the session begins.

The musician does not report this. The event has no name, and it lasted one
minute, and it never happened again. The musician files it under "new
device, first boot, computers". They are not wrong to do so, and this is
exactly why the fault survived for twelve years.

We must record what the musician could not know. That first boot was not
slow. It had already failed, and it would never have finished. The pedal
was not starting. It was waiting for a sound card that could not produce
sound, and it would have waited forever.

---

## 2. What the pedal reports about itself

A pi-Stomp in this state is confident and wrong. This matters, because the
confidence is what hides the fault from the musician and from us.

Ask the pedal whether it has a sound card, and it says yes:

```
$ cat /proc/asound/cards
 0 [IQaudIOCODEC   ]: IQaudIOCODEC - IQaudIOCODEC

$ aplay -l
card 0: IQaudIOCODEC [IQaudIOCODEC], device 0: IQaudIO CODEC HiFi v1.2 ...
```

Ask it whether the drivers loaded, and they did. Ask it whether the audio
DMA channels are connected to the i2s hardware, and they are. Ask the kernel
log for an error, and there is none. Not a warning, not a line.

Only one thing is wrong, and everything the musician cares about depends on
it:

```
$ aplay -D hw:0,0 /dev/zero
aplay: main:850: audio open error: Invalid argument
```

Every attempt to open the audio device fails with `EINVAL`. The failure
applies to playback and to capture, and it applies to the root user. JACK
is the first program to try, so JACK is the first to fail:

```
jackdrc: ALSA: Cannot open PCM device alsa_pcm for playback
jackdrc: Cannot initialize driver
jack.service: Scheduled restart job, restart counter is at 9.
jack.service: Start request repeated too quickly.
```

JACK gives up after nine attempts. `mod-host` needs JACK, so `mod-host`
fails. `mod-ui` needs `mod-host`, so `mod-ui` fails. The pi-Stomp
application waits for all of them, so the screen stops. The musician sees a
frozen splash screen, and the true cause is nine layers below it.

This is the first lesson of the field study. **The pedal fails at the
bottom, and it complains at the top.** A support report will say "the screen
freezes on first boot", and that sentence contains no useful information.

---

## 3. Following the failure down

`EINVAL` from an `open()` is a poor clue, because many things return it. We
must find the exact line. We used ftrace and kprobes on the running pedal,
and the answer came in five lines:

```
calchwr:  snd_soc_runtime_calc_hw          ret=0
socopen:  soc_pcm_open                     ret=0
cmask:    snd_pcm_hw_constraint_mask  var=0 mask=0
cmaskr:   snd_pcm_hw_constraint_mask       ret=-22
opensub:  snd_pcm_open_substream           ret=-22
```

Read this from the top. ASoC opens the stream and **reports success**. Then
the ALSA core applies its constraints, and it asks for the set of access
modes the hardware supports. The answer is `mask=0`, which means the
hardware supports no access mode at all. `-22` is `EINVAL`.

`mask=0` is built from `runtime->hw.info`. That structure is filled by the
platform half of the sound card, in `dmaengine_pcm_open()`. So we traced
every function in the five relevant modules during one `open()`, and we
found that **not one function from the generic dmaengine PCM code runs**.

Two further measurements agreed. `snd_soc_component_open()` is called twice,
and it must be called three times: once for the CPU DAI, once for the codec,
and once for the platform. The module reference count of
`snd_soc_bcm2835_i2s` is 1, and it must be 2.

The conclusion is precise. The card has a PCM device, and that PCM device
has no DMA engine behind it. It is a sound card with no path to the
speaker. The musician's guitar signal has nowhere to go, and the kernel
never says so.

---

## 4. Why the kernel builds a card like this

The fault is in `sound/soc/soc-core.c`, in `snd_soc_add_pcm_runtime()`. The
function binds the three halves of a sound card, and it treats them
differently:

```c
for_each_link_cpus(...)    if (!snd_soc_find_dai(cpu))   goto _err_defer;
for_each_link_codecs(...)  if (!snd_soc_find_dai(codec)) goto _err_defer;

/* Find PLATFORM from registered PLATFORMs */
for_each_link_platforms(dai_link, i, platform) {
    for_each_component(component) {
        if (!snd_soc_is_matching_component(platform, component)) continue;
        snd_soc_rtd_add_component(rtd, component);
    }
}
```

A missing CPU DAI defers, and a missing codec DAI defers. **A missing
platform does not defer.** The loop takes whatever matches at that instant,
and it takes nothing if nothing matches, and the card binds anyway.

Now look at the driver, `sound/soc/bcm/bcm2835-i2s.c`:

```
893:  ret = devm_snd_soc_register_component(...);   /* the CPU DAI */
900:  ret = devm_snd_dmaengine_pcm_register(...);   /* the platform  */
```

Those two registrations are seven lines apart, and they are not atomic. The
second one calls `dma_request_chan()` twice, and that call can sleep.

The machine driver, `sound/soc/bcm/iqaudio-codec.c`, matches its platform by
device tree node alone:

```c
dai->cpus->of_node      = i2s_node;
dai->platforms->name    = NULL;
dai->platforms->of_node = i2s_node;   /* same node as the CPU DAI */
```

Both i2s components live on that same node. So if the machine driver binds
between line 893 and line 900, the platform loop finds the CPU DAI
component, and it accepts it, and it stops. The CPU DAI component has no
`pcm_construct` and no `open`. That is the whole fault.

**Tie this back to the stage.** Seven lines of driver code, and a window of
perhaps one millisecond, decide whether a musician can hear their guitar.

---

## 5. Two routes into the window

We found two, and they produce the same card.

**The boot route.** `iqaudio-codec.c` calls `snd_soc_register_card()`, not
the `devm_` variant, so a deferral goes to the driver core rather than to
ASoC's own list. The driver core retries deferred probes on a workqueue, and
that worker runs on any CPU. When the DA7213 codec finishes binding, it
triggers that worker. The worker can then re-probe the machine driver on one
CPU while `bcm2835_i2s_probe()` sits between its two registrations on
another. This is the route the musician hits.

**The runtime route.** When a component of a live card is removed,
`snd_soc_del_component_unlocked()` puts the card on `unbind_card_list`. The
next `snd_soc_add_component()` rebinds it **immediately**, and the CPU DAI
registration is the next one. This route is deterministic, and we use it as
our test harness.

`PREEMPT_RT` widens both windows, because full preemption allows the i2s
probe thread to be stopped inside the window. The `davinci-mcasp` commit
described below names preemption explicitly.

---

## 6. The evidence, in full

Every number here was measured on one pedal, `psdev`.

### The bind state

| Measurement | Working card | Broken card |
| :--- | :--- | :--- |
| `open()` on the PCM | succeeds | `EINVAL` |
| `snd_soc_bcm2835_i2s` refcount | 2 | 1 |
| `snd_soc_iqaudio_codec` refcount | 3 | 0 |
| `pcm0p/sub0/prealloc` | 512 | not measured |
| `snd_soc_component_open()` calls | 3 expected, not traced | 2 |
| dmaengine PCM functions during open | not traced | never run |
| Kernel log output | none | none |

Two rows are marked because we did not measure them. We traced the broken
card in detail, and we then repaired it, so several counts exist for one
side only. The refcounts are the strongest pair, because we have both sides
of those from the same pedal.

### The component registration order

`/sys/kernel/debug/asoc/components` lists newest first, because
`snd_soc_add_component()` calls `list_add()`. Reversed, it gives the true
order, and the order is the whole story:

| Boot | Order (oldest to newest) | Result |
| :--- | :--- | :--- |
| First boot of the new card | i2s(CPU) → **da7213** → i2s(dmaengine) | failed |
| All later boots | i2s(CPU) → i2s(dmaengine) → da7213 | passed |
| Reverted config boot | da7213 → i2s(CPU) → i2s(dmaengine) | passed |

The codec must land between the two i2s registrations. In every other
position the card is correct.

### The failure rate

| Boot type | Count | Failures |
| :--- | ---: | ---: |
| First boot of a newly written card | 1 | **1** |
| Warm reboot, 3.3.1 config | 7 | 0 |
| Warm reboot, reverted config | 1 | 0 |
| Cold power-on, 3.3.1 config | 1 | 0 |

One failure in ten boots, and the failure was the first boot. This is the
number that matters, because **it is the boot the musician performs, and it
is the only one they perform on a new card.** The first boot expands the
filesystem, and it generates SSH host keys, and it runs `firstboot.service`.
Those tasks compete with the udev coldplug for CPU and for disk. Later boots
do none of that work, and later boots converge on one safe order.

### A false trail, recorded honestly

We first observed the failure with the 3.3.1 `[pi3]` config, and we observed
success after we reverted that block. We reported a link between the two.
That report was wrong, and we must say so plainly.

Later boots on the 3.3.1 config passed seven times out of seven. The config
does not decide the outcome. It can shift timing, because `core_freq_fixed=1`
pins the core clock, and the I2C divisor derives from the core clock, and the
DA7213 identification read runs over I2C. But the evidence for causation was
one boot of each config, and one boot of each config proves nothing.

We keep the 3.3.1 config, and we fix the fault instead.

---

## 7. The repair we ship today

`pistomp-audio` 1.0.0-2 adds `pistomp-pcm-check`. It runs before
`jack.service`, and it does four things:

1. It opens the PCM named by `JACK_DEVICE`. It stops if the open succeeds,
   or if the open returns `EBUSY`.
2. On `EINVAL` it finds the machine driver through
   `/sys/class/sound/cardN/device/driver`, and it unbinds the driver, and it
   binds the driver again.
3. It opens the PCM again, and it retries up to three times.
4. It runs `alsactl restore`, because a rebind returns the codec to its
   default levels.

One rebind is enough, and it is deterministic. Both i2s components are
registered by then, so the platform loop finds the correct one. Measured:

```
[pcm-check] /dev/snd/pcmC0D0p returns EINVAL: the platform component is not bound
[pcm-check] machine driver is snd-rpi-iqaudio-codec, device soc:sound
[pcm-check] rebind attempt 1 of 3
[pcm-check] repaired: card0 /dev/snd/pcmC0D0p opens (ok)
```

The unit runs **before** `pistomp-audio-irq.service`, and the order is not a
preference. A rebind releases the i2s DMA channels and requests them again,
which destroys the interrupt threads. We measured this. The thread IDs
changed from 430 and 432 to 2974 and 2975, and the priority fell from 90 to
50. If the IRQ resolver ran first, the musician would get audio back with
the wrong interrupt priority, and the pedal would produce dropouts under
load. Repair first, then raise.

The script refuses to rebind a driver that is not a platform driver, so a
USB sound card is never touched.

This repair reaches every deployed pedal over OTA. That is its purpose, and
it is the reason we did not simply patch the kernel and stop.

---

## 8. The permanent fix, and how to send it

The userspace repair hides the fault. It does not remove it. The kernel must
change, and the change is five lines.

### The patch

Swap the two registrations in `bcm2835_i2s_probe()`:

```c
	ret = devm_snd_dmaengine_pcm_register(&pdev->dev, NULL, 0);   /* first */
	if (ret) {
		dev_err(&pdev->dev, "Could not register PCM: %d\n", ret);
		return ret;
	}

	ret = devm_snd_soc_register_component(&pdev->dev,
			&bcm2835_i2s_component, &bcm2835_i2s_dai, 1);   /* second */
```

The machine driver defers on the CPU DAI, and only on the CPU DAI. If the
platform component is already registered when the CPU DAI appears, the
window cannot exist. The fix is structural, and it is not a timing change.

### This is not a new idea, and that is the strongest argument

The same bug class was found and fixed in seven other drivers. Cite them,
because a reviewer who recognises the pattern will read the patch quickly:

| Commit | Driver | Year |
| :--- | :--- | :--- |
| `9c3ad33b5a41` | `fsl_sai` | 2021 |
| `0adf292069dc` | `fsl_micfil` | 2021 |
| `f12ce92e98b2` | `fsl_esai` | 2021 |
| `ee8ccc2eb584` | `fsl_spdif` | 2021 |
| `c590fa80b392` | `fsl_xcvr` | 2021 |
| `ea532c29972d` | `fsl_aud2htx` | 2022 |
| `d18ca8635db2` | `davinci-mcasp` | 2024 |

The `fsl_sai` commit message states the problem in the maintainer's own
words:

> There is no defer probe when adding platform component to
> snd_soc_pcm_runtime(rtd) ... So if the platform component is not ready at
> that time, then the sound card still registered successfully, but platform
> component is empty, the sound card can't be used.

`bcm2835-i2s` never received the fix. It still has the original order from
its first commit, `c6aeb7de226d` (2013-11-22), and mainline today is
unchanged. We checked `patchwork.kernel.org` for every patch that has
touched the file, and none of the eighteen concerns probe order.

### Where to send it

Do not guess the recipients. Generate them:

```bash
./scripts/get_maintainer.pl -f sound/soc/bcm/bcm2835-i2s.c
```

Expect this set:

- **Mark Brown** `<broonie@kernel.org>` — the ASoC maintainer, and the person
  who applies the patch
- **alsa-devel@alsa-project.org** — the subsystem list, and the archive that
  matters
- **linux-kernel@vger.kernel.org** — the general list
- **linux-rpi-kernel@lists.infradead.org** and the BCM maintainers
- Send a separate pull request to `raspberrypi/linux` as well, so deployed
  Raspberry Pi kernels get the fix before it returns downstream from
  mainline.

Base the patch on Mark Brown's tree, not on `raspberrypi/linux`:

```
git://git.kernel.org/pub/scm/linux/kernel/git/broonie/sound.git  for-next
```

### The house style, and how to be taken seriously

The Linux mailing lists have a strict format. The format is not decoration.
A patch in the wrong format is often not read at all, and the author usually
never learns why.

**The mechanics.**

- Send plain text. Never send HTML, and never send an attachment. The patch
  must be in the body of the message.
- Use `git format-patch` and `git send-email`. Do not paste into a web mail
  client, because it will change whitespace and the patch will not apply.
- One patch does one thing. This patch changes an order, so it is one patch.
- Run `scripts/checkpatch.pl --strict` on the patch, and fix what it
  reports.
- Compile the file before you send it.

**The subject line.** Copy the accepted series exactly:

```
[PATCH] ASoC: bcm2835-i2s: register platform component before registering cpu dai
```

A reviewer who applied the `fsl` series in 2021 will recognise that sentence,
and recognition costs them no effort. This single choice does more for the
patch than any argument in the body.

**The tags, below the description and above the `---`.**

```
Fixes: c6aeb7de226d ("ASoC: Add support for BCM2835")
Cc: stable@vger.kernel.org
Signed-off-by: Your Name <your@email>
```

`Signed-off-by` is a legal statement under the Developer's Certificate of
Origin, so the name must be a real name. `Fixes:` lets the stable
maintainers route the patch automatically. `Cc: stable` is correct here,
because this is a user-visible fault with no log message.

**The description.** State the failure first, then the mechanism, then the
fix. Keep it factual, and do not argue. Give the reproduction, because a
reviewer who can reproduce a bug approves a patch faster than one who must
trust you:

```
    On a Raspberry Pi 3 with an IQaudio CODEC, the sound card sometimes
    binds with the CPU DAI component in place of the generic dmaengine
    PCM component. The card enumerates and aplay -l lists it, but every
    open() of the PCM returns EINVAL and nothing is printed to the log,
    because runtime->hw is never populated.

    bcm2835_i2s_probe() registers the CPU DAI component before the
    dmaengine PCM component. snd_soc_add_pcm_runtime() defers on a
    missing CPU DAI and on a missing codec DAI, but it does not defer on
    a missing platform. A machine driver that matches its platform by
    of_node (iqaudio-codec.c does) therefore matches the CPU DAI
    component if it binds between the two registrations.

    Register the platform component first, as was done for fsl_sai in
    commit 9c3ad33b5a41 ("ASoC: fsl_sai: register platform component
    before registering cpu dai") and for davinci-mcasp in commit
    d18ca8635db2 ("ASoC: ti: davinci-mcasp: Fix race condition during
    probe").

    Reproduced deterministically by unbinding and rebinding the i2s
    device, which puts the card on unbind_card_list and rebinds it at
    the CPU DAI registration:

      echo 3f203000.i2s > /sys/bus/platform/drivers/bcm2835-i2s/unbind
      echo 3f203000.i2s > /sys/bus/platform/drivers/bcm2835-i2s/bind
```

**After you send it.**

- Wait. A week of silence is normal, and two weeks is not unusual.
- Do not resend the same patch. Send a polite reply to your own message,
  and ask whether anything is needed.
- Reply below the quoted text, and delete the parts you do not answer. Do
  not write your reply above the quotation.
- If you change the patch, send `[PATCH v2]`, and put the list of changes
  below the `---` line. Text below `---` does not enter the commit history,
  and reviewers expect the changelog there.
- Accept review comments without argument, and make the change, or explain
  the technical reason clearly and briefly.

**What earns credibility here.** You have a measured failure, a deterministic
reproduction, a named precedent, and a five-line fix. That combination is
rare, and it is worth more than any amount of explanation. Present it
plainly, and let the reviewer reach the conclusion.

---

## 9. What we still do not know

1. **The true first-boot failure rate.** We have one failure in one first
   boot. To measure it we must write the image again, and boot it, and
   repeat. Every other boot type is a poor substitute.
2. **Whether a Pi 4 behaves the same.** The `[pi4]` config carries the same
   settings, and the same driver runs there. We have not measured it.
3. **Whether other cards are affected.** HiFiBerry and AudioInjector use
   different machine drivers on the same i2s platform. If they match their
   platform by `of_node`, they have the same fault. The repair is generic,
   so they are covered either way.
4. **Whether a rebind resets the mixer in every case.** We run `alsactl
   restore` as a precaution, and we have not measured the state before it.

---

## 10. The closing observation

The musician power-cycled the pedal, and the pedal worked, and the musician
played. They were right to do so, and their instinct was correct, and their
solution was correct.

The cost of that instinct is what interests the anthropologist. A fault that
a user can clear in ten seconds does not get reported, so it does not get
fixed, so it survives. This one survived twelve years in a driver that runs
on many millions of devices. It survived because it is silent, and because
the remedy is obvious, and because the people who hit it have a guitar in
their hands and a reason to move on.

We found it because a pedal on a bench had no musician to power-cycle it.
