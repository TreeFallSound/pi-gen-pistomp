# On-device debugging

## Debug symbols

`move_to_cache` routes any `-dbgsym` deb to `debugsyms/` (gitignored), not
`overrides/` — everything in `overrides/` lands in the image.

Two things suppress dbgsym generation, and you need both fixed:

```makefile
override_dh_auto_build:
	CFLAGS="-g" $(MAKE) LDFLAGS="-Wl,--no-undefined"
```

`CFLAGS` via env because the upstream Makefile `+=` onto it; `LDFLAGS` on the
command line because that's the only way to drop a hardcoded `-s` (mod-host
has one). Restate any flag the Makefile also adds. `dh_strip` still strips the
shipped binary — symbols just go to the `-dbgsym` package.

Install both debs on the device, then `gdb` resolves source lines. Also install
`libc6-dbg` if you need locals inside glibc (`_int_malloc` etc.).

## Temporary debug config

Drop-ins in `/etc/systemd/system/<unit>.d/` survive dpkg upgrades — the units
ship to `/usr/lib/systemd/system/`.

```ini
[Service]
LimitCORE=infinity
Environment=MALLOC_CHECK_=3
Environment=MALLOC_PERTURB_=165
```

`Environment=` in a drop-in appends; it does not replace the unit's own.
Env is fixed at exec — removing the drop-in does nothing until a restart.

With `MALLOC_PERTURB_=165`, `0xA5` = freed, `0x5A` = malloc'd-uninitialised.
Both are visible in any hexdump, which is how you spot use-after-free.

## Valgrind

```ini
[Unit]
OnFailure=
[Service]
Type=simple
PIDFile=
Restart=no
CPUSchedulingPolicy=other
UnsetEnvironment=MALLOC_CHECK_ MALLOC_PERTURB_
ExecStart=
ExecStart=/usr/bin/valgrind --tool=memcheck --error-limit=no --num-callers=40 \
    --track-origins=yes --log-file=/tmp/valgrind-%%p.log \
    /usr/bin/mod-host -n -p 5555 -f 5556
```

- `%p` is a systemd specifier — escape it as `%%p` or you get the unit name.
- Run the daemon non-forking (`-n` for mod-host) with `Type=simple`.
- Drop `CPUSchedulingPolicy` off FIFO. Valgrind serialises threads; a 20-50x
  slower process at RT priority starves the box.
- `Restart=no` + cleared `OnFailure=` stop restart thrash mid-diagnosis, but
  they also disable the stack's self-healing. Remember to put them back.
- Startup is slow enough that mod-ui gives up on mod-host ("Host failed to
  initialize") and exits. Start mod-host, wait for it to listen on 5555, then
  start mod-ui.

**Valgrind cannot run ARMv8.3 binaries.** Upstream rpi5 builds use `LDAPR`
(`unhandled instruction 0xF8BFC001`) and die with SIGILL before reaching your
bug. Use a baseline `-march=armv8-a` build of the plugin instead.

Memcheck reports invalid writes whether or not they crash — a clean run under
valgrind is not an all-clear, since the slowdown changes thread interleaving
and can hide a race entirely.

## Heap corruption

The crash site is not the bug. glibc aborts (`unsorted double linked list
corrupted`, or SIGSEGV in `unlink_chunk`) on whatever innocent `malloc`/`free`
next touches the damaged chunk. Backtraces name the detector, not the writer.

Walk the arena in gdb instead and look at *which* field was clobbered — damage
confined to `fd` with `bk` intact means a stale-pointer write into a freed
block, not an overflow. Then let valgrind name both ends.
