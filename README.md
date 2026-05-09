# Overlays — NextUI Pak

Browse, preview and install community overlays for libretro emulators on
[NextUI](https://github.com/LoveRetro/NextUI), straight from your handheld.

The overlay artwork comes from
[LoveRetro/nextui-community-overlays](https://github.com/LoveRetro/nextui-community-overlays).
Credit for the artwork itself stays with the original authors (KrutzOtrem,
SkyWalker541, drkhrse, mugwomp93, ...).

## What it does

- Loads the index of community overlays in one request from the GitHub API
- Filters by your device's resolution (auto-detected for tg5040 Brick / Smart Pro)
- Lets you pick a system, scroll through every overlay PNG, see a fullscreen
  preview, then install with one button
- **Installs to all installed emu variants for that system** — e.g. picks a GBA
  overlay, your Brick has `MGBA.pak`, the file goes to `/Overlays/MGBA/`
  (and the resolution-aware `/Overlays/<RES>/MGBA/`) so NextUI actually shows
  it under `Options → Frontend → Overlay`
- Auto-generates a libretro `.cfg` next to every PNG that ships without one,
  otherwise NextUI silently ignores the artwork

## Install

### Via Pak Store *(recommended once accepted)*

`Tools → Pak Store → Browse → Overlays → Install`

### Manually

1. Grab the latest [release](../../releases) (`Overlays.pak.zip`).
2. Unzip — you should get an `Overlays.pak/` folder.
3. Copy `Overlays.pak/` to `/Tools/tg5040/` on your SD card.
4. Eject, boot the device, run `Tools → Overlays`.

## How it works

```
[CORE]/[res]/[Author]/[subdir]/file.png
                ^                ^
                |                +-- displayed as "<file> [Author]" in the picker
                |
                +-- 480p / 720p / 768p, picked by your device
```

For each install the pak:

1. Resolves the system (e.g. `GBA`) into all aliases your device has paks for
   (`GBA → MGBA, GBA, GPSP, ...`)
2. Writes the PNG to both `/Overlays/<TAG>/` and `/Overlays/<RES>/<TAG>/`
3. Either downloads the sibling `.cfg` from the repo and rewrites the
   `overlayN_overlay = ...` reference, or generates a default cfg

## Development

The pak is one POSIX-`sh` script (no `jq`, no Python, busybox-friendly).

- Iteration helper: `./deploy.sh` (autodetects mounted SD card → adb → ssh)
- Build a release zip: `./release.sh`
- Cut a release with `gh`: `./release.sh v0.2.0`

The script bootstraps `minui-list` and `minui-presenter` from
[josegonzalez](https://github.com/josegonzalez)'s releases on first run.

## Caveats

- Overlays only work with libretro cores. Standalone emulator paks ignore them.
- The repo currently has 0 overlays at `720p`. On TrimUI Smart Pro the pak
  auto-falls-back to `768p` (or `480p`).
- HTTPS verification is disabled when the device has no CA bundle (e.g.
  Brick) — same trade-off as every other community pak that calls out to
  GitHub.

## Credits

- Artwork: every contributor in
  [LoveRetro/nextui-community-overlays](https://github.com/LoveRetro/nextui-community-overlays)
- `minui-list` / `minui-presenter`: [@josegonzalez](https://github.com/josegonzalez)
- NextUI: [@LoveRetro](https://github.com/LoveRetro)

## License

GPL-3.0 (see `LICENSE`). Overlay images keep their original authors' licenses.
