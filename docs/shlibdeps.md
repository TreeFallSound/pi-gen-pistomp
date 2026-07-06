# Why we (almost) never hand-write runtime library deps

When a package links against a shared library, you usually only add the
`-dev` package to **`Build-Depends`** — the runtime library dependency is
derived automatically. Here's the machinery.

## `DT_NEEDED` is an ELF thing, not a Debian thing

When the linker builds a `.so` (or executable), every shared library it links
against is recorded as a `DT_NEEDED` entry in the binary's dynamic section.
It's baked into the file. At runtime the dynamic loader (`ld.so`) walks those
entries to know what to load.

```bash
readelf -d loopjefe.so | grep NEEDED
#  (NEEDED) Shared library: [librubberband.so.2]
#  (NEEDED) Shared library: [libc.so.6]
```

The recorded name is the **soname** (`librubberband.so.2`) — the versioned
name, not the dev symlink (`librubberband.so`) and not the full filename
(`librubberband.so.2.3.0`). That middle-versioned name is the ABI contract:
bump the soname and it's a different, incompatible library. This is standard
ELF/glibc behaviour, identical on any Linux.

## Debian's part: soname → package dependency

`dh_shlibdeps` (via `dpkg-shlibdeps`) turns those sonames into a package dep:

1. Scan the built binary, extract each `DT_NEEDED` soname.
2. Ask dpkg which installed package provides that soname — answered by each
   library package's shlibs/symbols file
   (e.g. `/var/lib/dpkg/info/librubberband2.shlibs`).
3. Resolve to `librubberband2 (>= 3.3.0)` and substitute it into
   `${shlibs:Depends}` in `debian/control`.

So `${shlibs:Depends}` in the runtime `Depends:` line already covers every
shared library the binary links. You add `<lib>-dev` to `Build-Depends`; the
matching runtime package flows in on its own.

(RPM does the equivalent with `find-requires`, producing deps like
`librubberband.so.2()(64bit)`.)

## Worked example: loopjefe-lv2 → rubberband

- `debian/control` `Build-Depends: … librubberband-dev, pkg-config` — headers,
  `rubberband.pc`, and the `librubberband.so` link symlink for build time.
- The plugin Makefile links `pkg-config --libs rubberband` → `-lrubberband`,
  which the linker resolves via `librubberband.so` (ld prefers the `.so` over
  the shipped `.a` when both are present) → records
  `NEEDED librubberband.so.2`.
- `dh_shlibdeps` maps that to `librubberband2`, injected through the existing
  `${shlibs:Depends}`. No runtime dep was hand-written.
