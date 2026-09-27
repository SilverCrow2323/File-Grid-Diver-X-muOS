# File-GD X

<p>
  <img alt="platform" src="https://img.shields.io/badge/platform-muOS%20%C2%B7%20RG35XX%20H-0d0d1a?labelColor=1a1a2e">
  <img alt="engine" src="https://img.shields.io/badge/engine-L%C3%96VE%2011.5%20%2F%20LuaJIT-00ffcc?labelColor=1a1a2e">
  <img alt="version" src="https://img.shields.io/badge/version-v1.5.0-ff00ff?labelColor=1a1a2e">
  <img alt="license" src="https://img.shields.io/badge/license-GPL--3.0--or--later-0d0d1a?labelColor=1a1a2e">
  <a href="https://github.com/SilverCrow2323/File-Grid-Diver-X-muOS/actions/workflows/ci.yml">
    <img alt="CI" src="https://github.com/SilverCrow2323/File-Grid-Diver-X-muOS/actions/workflows/ci.yml/badge.svg">
  </a>
</p>

```
┌──────────────────────────────────────────────────────────┐
│  F I L E - G D   X                                        │
│  the system console for a muOS handheld                   │
└──────────────────────────────────────────────────────────┘
```

A gamepad-native, dual-pane file manager for **muOS** on the **Anbernic
RG35XX H** (and compatible devices), built with [LÖVE 11.5](https://love2d.org/)
and LuaJIT. It's the file manager, the diagnostics panel, the storage
janitor, and the plugin hub your handheld didn't come with — plus one
thing it definitely didn't come with either (see [Easter egg](#easter-egg)).

Part of the **SPDW Factory** family of tools.

---

## Table of contents

- [Highlights](#highlights)
- [Controls](#controls)
- [Installation](#installation)
- [The plugin system](#the-plugin-system)
- [Storage & diagnostics](#storage--diagnostics)
- [Easter egg](#easter-egg)
- [Directory layout](#directory-layout)
- [Configuration](#configuration)
- [Development](#development)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License & credits](#license--credits)

---

## Highlights

**Core file manager**
- **Dual pane.** Two directories side by side, switch focus with one
  button, copy from one to the other in two keystrokes.
- **Four view modes.** List, Grid, Compact, Details.
- **Real archives.** Create/extract `.zip`, `.tar`, `.tar.gz`; extract
  also `.tar.bz2`, `.tar.xz`, `.7z`, `.gz` (system tools, nothing
  bundled) — and, with the Archive Extender plugin, `.rar`, `.iso`,
  `.img`, `.tar.zst`, `.cbr`/`.cb7`/`.cbt` on top.
- **Trash with restore**, per-volume, indexed and browsable.
- **Undo stack.** One press reverses the last mutating action —
  rename, batch rename, copy, cut, trash, mkdir, touch — single file
  or a whole batch counts as one entry.
- **Batch rename** with a live preview and `{name}` `{ext}` `{n}`
  `{nn}` `{nnn}` `{lower}` `{upper}` tokens.
- **Checksums** (MD5 / SHA-1 / SHA-256) for verifying ROMs and backups.
- **Small-file text editor** with atomic save, `.bak` rotation, and a
  status bar (line endings, encoding, syntax, cursor, dirty flag).
- **In-app search**, quick filter and a non-blocking recursive search.

**System layer**
- **Storage hub** — one screen, four sections: volume list with usage
  bars, a per-category disk analyzer (ROM/video/audio/image/archive),
  a content-hash duplicate finder, and a one-tap cleanup for trash,
  logs, downloads and snapshots.
- **Diagnostics** — CPU, kernel, uptime, temperature, battery, RAM,
  network interfaces, mounted volumes, a live pad tester.
- **GRID-DEV console** — a dedicated settings sub-app for
  performance, debug, system behaviour and network toggles.
- **NTP time sync** for muOS builds without a battery-backed RTC.
- **Native launcher glyph**, so it shows up in `MUOS/application/`
  with its own icon and category — no menu spelunking required.

**Plugins, not bloat**
Everything past "manage my files" lives behind a permissioned plugin
system (see [below](#the-plugin-system)), so the base app stays a
file manager first.

---

## Controls

### Main menu

| Input           | Action          |
| --------------- | --------------- |
| D-pad up / down | Move selection  |
| A               | Enter           |
| B               | Quit            |
| Any key         | Skip intro      |

### File manager

| Input           | Action                                                          |
| --------------- | ---------------------------------------------------------------|
| D-pad           | Move selection                                                  |
| A               | Open folder / file                                              |
| B               | Parent folder                                                   |
| X               | Cycle filter (all / dirs / files / img / audio / video / text)  |
| Y               | Cycle sort (name / size / date / type)                          |
| L2 / R2         | Cycle view (list / grid / compact / details)                    |
| L1 / R1         | Previous / next page                                            |
| SPACE           | Toggle mark on the current item                                 |
| START           | Open the SPDW side panel                                        |
| Ctrl+A          | Mark every item in view                                         |
| Ctrl+C / X / V  | Copy / cut / paste                                              |
| Ctrl+Z          | Undo last operation                                              |
| F2              | Rename                                                           |
| DEL             | Move to trash                                                    |
| Shift+DEL       | Permanent delete (confirmation required)                        |
| N / F           | New folder / new file                                            |
| M               | Action menu for the focused item                                 |
| P               | Properties (size, perms, owner, symlink target, chmod, checksum) |
| R               | Batch rename (2+ marked items)                                   |
| C               | Compute checksum                                                 |
| Z / T           | Compress selection to `.zip` / `.tar.gz`                         |
| U / I           | Extract archive here / into its own folder                       |
| E               | Open in the text editor                                          |
| ESC             | Quit                                                             |

### Dual pane

| Input  | Action                    |
| ------ | ------------------------- |
| Ctrl+D | Toggle dual pane          |
| Tab    | Switch the active pane    |
| D-pad  | Navigate the active pane  |

All single-pane shortcuts apply to whichever pane has focus.

---

## Installation

### On muOS

1. Insert the SD card into your PC.
2. Copy the `File-GD X/` folder into `MUOS/application/` on the card:

   ```
   /media/<your-user>/<SD-LABEL>/MUOS/application/File-GD X/
   ```

3. Eject cleanly, insert the card into the RG35XX H, boot muOS, and
   pick **File-GD X** from the **Utilities** category.

Prebuilt `.muxapp` packages are attached to each
[GitHub Release](https://github.com/SilverCrow2323/File-Grid-Diver-X-muOS/releases)
instead of living in the repo — grab one from there if you don't want
to build.

Logs are written to `data/logs/fgd_<timestamp>.log`; the latest is
symlinked at `data/logs/latest.log`.

### On desktop (for testing)

LÖVE 11.5 is required.

```sh
# Debian / Ubuntu
sudo apt install love

# Fedora
sudo dnf install love

# Arch
sudo pacman -S love

# macOS
brew install --cask love
```

Then, from the project root:

```sh
love .
```

or, to capture a full session log:

```sh
./deploy_desktop.sh
```

Logs land in `.desktopbase/logs/`.

---

## The plugin system

A plugin is a folder under `plugins/` with a `plugin.lua` manifest and
a `main.lua` entry point. Six ship today:

| Plugin              | Category    | What it does                                          |
| -------------------- | ----------- | ------------------------------------------------------ |
| **Chou Henka**       | Media       | Media center — library, player, EQ, visualizer, video   |
| **Disk Doctor**      | Diagnostics | Guided wizard to free up disk space                     |
| **Input Holmes**     | Diagnostics | A study in input mapping — diagnoses pad/key issues     |
| **Office Reader**    | Extensions  | View `.docx`, `.xlsx`, `.pptx` files                    |
| **Web View**         | Extensions  | HTML rendering via a built-in Lua parser (no download)  |
| **Archive Extender** | Extensions  | Unlocks RAR, ISO, IMG, 7z, TAR.ZST via `7z`/`unrar`      |

PDF support (`pdf_lib`, a bundled PyMuPDF) is offered as an in-app
**download-on-demand** rather than a vendored dependency — it's large,
so it isn't part of the base install or the repo.

**Permissions.** Nothing a plugin does is implicit. `plugins/api.lua`
gates `io`, `os.execute`/`io.popen`, and cross-plugin `require` behind
a small permission catalog (`filesystem.read`, `filesystem.write`,
`shell.exec`, `love.filesystem`). The first time a plugin needs one,
a consent screen asks; grants persist to `data/plugin_perms.json` and
can be revoked per-plugin at any time. Plugins that only touch the
app's own trusted wrappers (`services.fs`, `ui.*`, `core.*`) need no
permission at all. `print()` inside a plugin is routed to
`data/fgd_runtime.log` with a `[plugin <name>]` prefix instead of
going to stdout.

Writing your own: see [`plugins/README.md`](plugins/README.md) for
the manifest shape and the full permission/sandbox reference.

---

## Storage & diagnostics

- **VOLUMES** — every mount point, free/total bars, remount actions.
- **ANALYZE** — usage broken down by ROM / video / audio / image /
  archive / other, with a recoverable-space summary.
- **DUPLICATES** — content-hash (size pre-filter + MD5) duplicate
  finder with per-group keep/drop and a one-tap move-to-trash.
- **CLEANUP** — wipe trash, logs, downloads, temp, and snapshots in
  one pass.
- **GRID-DEV** — performance, debug/diag, system behaviour, and
  network toggles behind a dedicated console (Settings → GRID-DEV).

---

## Easter egg

There's a hidden retro one-on-one fighting screen tucked behind the
main menu, unlocked with a Konami-style input on boot, complete with
its own music, background art, and a floating mascot with selectable
variants. It's a love letter to a certain '90s PS1 fighting game, not
a commercial feature — non-commercial fan homage, no affiliation with
the original rights holders. If you're forking this for a wider or
commercial release, that folder (`assets/**/fb/`,
`screens/*_fb*.lua`, `ui/finalbout.lua`) is the first thing to strip
or replace.

---

## Directory layout

```
File-GD X/
├── main.lua                entry point, screen registry, nav stack
├── conf.lua                LÖVE window config + global error handler
├── mux_launch.sh           muOS launcher (suspends the volume OSD)
├── deploy_desktop.sh       desktop launcher with session logging
├── build_release.sh        packages a .muxapp for release
├── CHANGELOG.md
├── LICENSE
│
├── core/                   native bootstrap, state, input map, audio,
│                           json, clipboard, log
├── ui/                     frame, draw, glyph, keyboard, modal, notify,
│                           properties, transition, finalbout
├── screens/                mainmenu, grid, editor, image_viewer, search,
│                           settings, storage, grid_dev, plugins,
│                           fgd_plugins, device, about, pad_test, ...
├── services/                fs, fs_async, archive, archive_rt, trash,
│                           checksum, catalog, operations, dspace
├── plugins/                chou_henka, disk_doctor, input_holmes,
│                           office_reader, web_view, archive_extender,
│                           api.lua (permissions), loader.lua
├── themes/                 blame, gc, wii
├── tests/                  busted specs
├── tools/                  build_native.sh, check_syntax.sh, run_tests.sh
├── assets/                 fonts, images, sfx
├── glyph/                  muOS launcher icons
├── lib/                    bundled LÖVE runtime + native extensions
└── data/                   runtime state (gitignored)
    ├── logs/
    ├── trash/
    └── fgd.json
```

---

## Configuration

Settings persist to `data/fgd.json`, created on first run and updated
whenever a toggle changes:

```json
{
  "general": {
    "theme": "blame",
    "view": "list",
    "show_hidden": false,
    "sort_asc": true,
    "dual": false
  },
  "sort": { "key": "name", "folders_first": true },
  "ui": { "show_fps": false, "particles": true },
  "sound": { "enabled": true, "volume": 0.55 },
  "last_cwd": "/mnt/mmc"
}
```

Edit it by hand or through the **Settings** screen. Three built-in
themes ship: `blame`, `gc`, `wii`.

---

## Development

Nothing to build in the usual sense — this is Lua. To iterate locally:

```sh
git clone https://github.com/SilverCrow2323/File-Grid-Diver-X-muOS.git "File-GD X"
cd "File-GD X"
love .
```

**Testing.** `tests/` holds `busted` specs for the pure-Lua modules
(`fs`, `json`, `operations`, `grid_helpers`, settings store). Run them
with `tools/run_tests.sh` or `busted tests/`.

**Linting.** `luacheck .` (config in `.luacheckrc`, `lua51+love`
standard).

**CI.** `.github/workflows/ci.yml` runs three jobs on every push/PR:
`luacheck`, `busted` (pure-Lua path), and `busted` again with the
native `lfs`/`cjson` modules installed.

**Optional native extensions.** No Lua libraries are vendored; the
app runs on stock LuaJIT with pure-Lua fallbacks for everything. The
native `lfs`/`cjson` modules (built via `tools/build_native.sh`) are
purely a speed-up for large directory listings and are auto-detected
at boot (`core/native.lua`) — the app works fine without them.

---

## Troubleshooting

**Blue error screen on launch.** LÖVE's built-in error overlay. Check
`data/fgd_error.log`, or run `love . 2>&1 | tee /tmp/fgd.log` for a
live trace.

**Display freezes after launch on muOS.** The volume OSD daemon can
steal the framebuffer. Launch through `mux_launch.sh`, which suspends
it for the session and restores it on exit.

**File listing shows `--` for dates/sizes.** The device's `stat` isn't
GNU-compatible; `services/fs.lua` falls back to parsing `ls -lan`,
which loses precise timestamps. Expected on minimal BusyBox builds.

**"tool missing" on archive operations.** Delegated to system `zip`,
`unzip`, `tar`, `7z`. Check what's actually on the device:

```sh
command -v zip unzip tar 7z
```

`7z` is often absent on a bare muOS install; the app reports the
missing tool by name instead of failing silently.

**NTP sync fails.** `ntpdate`/`sntp` are often missing; the app falls
back to `busybox ntpd -q`. If neither exists, set the time manually
from the System screen.

**Logs, if something looks wrong:** `.desktopbase/logs/latest.log`
(desktop) or `data/logs/latest.log` (muOS) for session logs;
`data/fgd_runtime.log` for internal warnings; `data/fgd_error.log`
for the global error handler's output.

---

## Roadmap

### Shipped
- [x] Dual-pane file manager, 4 view modes
- [x] Archives, trash + restore, undo stack, batch rename, checksums
- [x] Storage hub (volumes / analyze / duplicates / cleanup)
- [x] GRID-DEV console, native bindings layer
- [x] Plugin system with permissions + sandbox, 6 plugins
- [x] Text editor, image viewer, in-app search
- [x] Test suite + CI (luacheck, busted)

### Planned
- [ ] FAT32 filename sanitizer
- [ ] Custom keybinding editor
- [ ] Theme schema validator
- [ ] Automated screen tests
- [ ] Real screenshots in this README

### Explicitly out of scope
- Embedded terminals / SSH from a PC
- HTTP / SFTP / FTP servers, cloud sync
- Hex *editing* (read-only hex view only)
- ROM auto-organizers

---

## License & credits

**GPL-3.0-or-later** — see [`LICENSE`](LICENSE).

Built on the muOS interface conventions and LÖVE infrastructure shared
with this author's other SPDW Factory projects for the RG35XX H.

- **sirpips** (SilverCrow2323) — design, code, and a stubborn refusal
  to ship a bad UI.
- **SPDW Factory** — the umbrella this tool lives under.
- **The LÖVE team** — for a runtime that fits on a handheld.
- **The muOS community** — for keeping the RG35XX H interesting.

If this tool saves your data, your time, or your sanity, tell someone
who owns an Anbernic.
