# File-GD X

> The system console for a muOS handheld.

A dual-pane file manager for **muOS** on the **Anbernic RG35XX H** and
compatible devices. Built with [LÖVE 11.5](https://love2d.org/) and LuaJIT,
designed for gamepad-only operation, SD-card safety, and the kind of
dense, no-nonsense UI that a handheld actually needs.

Part of the **SPDW Factory** family of tools.

---

## Table of contents

- [Highlights](#highlights)
- [Screens](#screens)
- [Controls](#controls)
- [Installation](#installation)
  - [On muOS](#on-muos)
  - [On desktop](#on-desktop)
- [Feature reference](#feature-reference)
- [Directory layout](#directory-layout)
- [Configuration](#configuration)
- [Building from source](#building-from-source)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [License](#license)
- [Credits](#credits)

---

## Highlights

- **Single-screen focus.** Opens directly on the file manager. No
  launcher maze, no mode you have to escape from.
- **Dual pane.** Two directories side by side, switch focus with one
  button, copy from one to the other with two keystrokes.
- **Four view modes.** List (with size, date, type), Grid, Compact
  (three columns), Details (metadata block per row).
- **Real archive support.** Zip, tar, tar.gz, tar.bz2, tar.xz, 7z, gz.
  Create and extract, with a preview listing before you commit.
- **Trash with restore.** Deletes go to a local trash index, not to the
  void. Undo a bad tap hours later.
- **Batch rename.** Pattern-driven, with preview, using `{name}`, `{ext}`,
  `{n}`, `{nn}`, `{nnn}`, `{lower}`, `{upper}` tokens.
- **Checksums.** MD5, SHA-1, SHA-256 for verifying ROMs and backups.
- **Disk tools.** Free space, mounted volumes, chmod, symlinks, all from
  the file manager.
- **NTP time sync.** Because a muOS clock without battery is a muOS
  clock that lies about when you saved your game.
- **Native glyph for the muOS launcher.** Your app appears in
  `MUOS/application/` with its own icon, category, and boot animation.
- **Keyboard + gamepad.** Every action reachable from a d-pad, and every
  menu item also mapped to a physical key for desktop testing.

---

## Screens

> Screenshots coming soon.

- **Main menu** — title intro, five sections (File Xplorer, System,
  Settings, Plugins, Exit), animated selection cards.
- **File manager** — list view with metadata columns.
- **Dual pane** — left and right directory trees, active pane
  highlighted.
- **Properties dialog** — size, permissions, owner, modified date,
  symlink target, inline chmod toggles.
- **Batch rename preview** — shows the first six renames before
  applying.
- **System diagnostics** — CPU, kernel, uptime, temperature, memory,
  network interfaces, mounted volumes.

---

## Controls

### Main menu

| Input           | Action          |
| --------------- | --------------- |
| D-pad up / down | Move selection  |
| A               | Enter           |
| B               | Quit            |
| Any key         | Skip intro      |

### File manager (single pane)

| Input           | Action                                        |
| --------------- | --------------------------------------------- |
| D-pad           | Move selection                                |
| A               | Open folder / file                            |
| B               | Parent folder                                 |
| X               | Cycle filter (all / dirs / files / img / audio / video / text) |
| Y               | Cycle sort (name / size / date / type)        |
| L2 / R2         | Cycle view (list / grid / compact / details)  |
| L1 / R1         | Previous / next page                          |
| SPACE           | Toggle mark on the current item               |
| START           | Open the SPDW side panel                      |
| Ctrl+A          | Mark every item in view                       |
| Ctrl+C / X / V  | Copy / cut / paste                            |
| F2              | Rename                                        |
| DEL             | Move to trash                                 |
| Shift+DEL       | Permanent delete (requires confirmation)      |
| N               | New folder                                    |
| F               | New file                                      |
| M               | Action menu for the focused item              |
| P               | Properties dialog                             |
| R               | Batch rename (requires 2+ marked items)       |
| C               | Compute checksum (MD5)                        |
| L               | Create symlink pointing to the focused item   |
| E               | Open focused file in the text editor          |
| Z               | Compress selection to `.zip`                  |
| T               | Compress selection to `.tar.gz`               |
| U               | Extract focused archive here                  |
| I               | Extract focused archive into its own folder   |
| ESC             | Quit                                          |

### File manager (dual pane)

| Input       | Action                    |
| ----------- | ------------------------- |
| Ctrl+D      | Toggle dual pane          |
| Tab         | Switch the active pane    |
| D-pad       | Navigate the active pane  |

All the single-pane shortcuts apply to whichever pane has focus.

### SPDW side panel (open with START)

| Input     | Action        |
| --------- | ------------- |
| D-pad     | Move          |
| A         | Activate      |
| B / START | Close panel   |

---

## Installation

### On muOS

1. Insert the SD card into your PC.
2. Copy the folder `File-GD X/` into
   `MUOS/application/` on the SD card. On most muOS builds that path is:

   ```
   /media/<your-user>/<SD-LABEL>/MUOS/application/File-GD X/
   ```

3. If you cloned this repo, use the bundled helper:

   ```sh
   ./prepare_sd.sh /media/<your-user>/<SD-LABEL>
   ```

   Or, to produce a portable tarball to move manually:

   ```sh
   ./prepare_sd.sh --pack
   ```

4. Eject the SD card cleanly, insert it into the RG35XX H, boot muOS,
   and pick **File-GD X** from the **Utilities** category.

Logs are written to `data/logs/fgd_<timestamp>.log`. The latest is
symlinked at `data/logs/latest.log`.

### On desktop

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

## Feature reference

### File operations

- **Copy / cut / paste** between panes or within a pane. Cross-device
  operations fall back to copy-then-delete. Name collisions are
  resolved automatically with a numeric suffix.
- **Multi-selection.** Mark items with SPACE, act on the whole set.
  Marks are shown with a leading `*` and a cyan highlight.
- **Rename.** Single file rename via F2. Batch rename via R with
  pattern tokens and a preview of the first six results.
- **Delete.** Default is soft delete to `data/trash/`. The trash is
  indexed, browsable, and restorable from the SPDW panel. A separate
  hard-delete command requires a confirmation modal.
- **Properties.** Full size, permissions, owner, group, modified time,
  and symlink target. Includes inline chmod toggles for user, group,
  and other, and a one-tap checksum.

### Archives

Supported formats:

| Create           | Extract          |
| ---------------- | ---------------- |
| `.zip`           | `.zip`           |
| `.tar`           | `.tar`           |
| `.tar.gz`        | `.tar.gz`        |
|                  | `.tar.bz2`       |
|                  | `.tar.xz`        |
| `.7z` (if `7z`)  | `.7z` (if `7z`)  |
|                  | `.gz`            |

Uses system `zip`, `unzip`, `tar`, and `7z` where available. Nothing is
bundled; if a tool is missing, the command reports it clearly instead
of failing silently.

### Search

In-folder quick filter with `/`. Recursive search with a separate
screen, powered by a detached shell job that writes results to `/tmp`
and polls for completion — the UI never blocks.

### Storage

- Free space indicator in every pane header.
- Volume list with per-mount usage bar in the SPDW panel.
- Mount options visible (ro, rw, sync, noatime).
- NTP time synchronization for muOS builds that ship without a real
  RTC.

### Diagnostics

- **System screen:** CPU model, kernel, uptime, temperature, battery,
  RAM usage with color-coded bar, network interfaces with IPv4, mounted
  volumes.
- **Log screen:** latest session log, live tail, filter by level.
- **Pad test screen:** every button, stick, and trigger visualized with
  live state.
- **Header:** clock, wifi signal with LED, battery, RAM, all as
  hand-stamped metal plaques.

### Editor

A small-file text editor for configs, scripts, and notes.

- Files up to 512 KB. Larger files open read-only.
- Preserves line endings (LF / CRLF) and BOM.
- Atomic save with `.fgd.bak` rotation.
- On-screen keyboard plus physical keyboard support.
- Status bar with line ending, encoding, detected syntax, cursor
  position, file size, dirty flag.

### Cosmetic

- Boot animation on launch (1.5 seconds, skip with any key).
- Main menu intro: title glitch, red X carved with a brush, staggered
  card entrance.
- CRT overlay (scanlines, vignette, subtle static).
- Hand-stamped metal plaques for header devices.
- Theme system: three built-in themes (`blame`, `gc`, `wii`).

---

## Directory layout

```
File-GD X/
├── main.lua                entry point
├── conf.lua                LÖVE config + global error handler
├── mux_launch.sh           muOS launcher
├── deploy_desktop.sh       desktop launcher with logging
├── prepare_sd.sh           SD card staging helper
├── README.md
├── LICENSE
│
├── core/                   state, settings, input, json, audio, clipboard
├── ui/                     frame, draw, glyph, keyboard, modal, notify,
│                           properties, multitool, batchrename
├── screens/                mainmenu, grid, editor, image_viewer, search,
│                           settings, log, about, pad_test, operations,
│                           disk_tools, device, plugins
├── services/               fs, fs_async, archive, trash, checksum, dspace
├── themes/                 blame, gc, wii
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

Settings persist to `data/fgd.json`. The file is created on first run
and updated whenever you change a toggle.

```json
{
  "general": {
    "theme": "blame",
    "view": "list",
    "show_hidden": false,
    "sort_asc": true,
    "dual": false
  },
  "sort": {
    "key": "name",
    "folders_first": true
  },
  "ui": {
    "show_fps": false,
    "particles": true
  },
  "sound": {
    "enabled": true,
    "volume": 0.55
  },
  "last_cwd": "/mnt/mmc"
}
```

You can edit this by hand or through the **Settings** screen.

---

## Building from source

Nothing to build in the usual sense: this is Lua. If you want to test
locally:

```sh
git clone <this-repo> "File-GD X"
cd "File-GD X"
love .
```

### Optional native extensions

Two pure-Lua libraries are vendored:

- `vendor/lume.lua` — table and string utilities.
- `vendor/inspect.lua` — pretty-printer for tables.

They are optional. Nothing in the file manager requires them; they
exist for diagnostics and future features.

### Compiling `lfs` and `cjson` for muOS (aarch64)

Requires a cross-toolchain. This is **not required** to run the app.
The pure-Lua fallbacks work; the native extensions just make large
directory listings faster.

```sh
sudo apt install gcc-aarch64-linux-gnu libc6-dev-arm64-cross \
                 libluajit-5.1-dev

mkdir -p build && cd build
git clone --depth 1 https://github.com/lunarmodules/luafilesystem
cd luafilesystem

aarch64-linux-gnu-gcc -O2 -fPIC -shared \
  -I/usr/include/luajit-2.1 \
  src/lfs.c -o ../../lib/aarch64/lfs.so
```

The loader in `core/native.lua` (if present) picks the right `.so` for
the current architecture and falls back silently if a library is
missing.

---

## Troubleshooting

### The app crashes on launch and shows a blue screen

LÖVE 11.5 shows a blue error overlay on unhandled errors. Look at
`data/fgd_error.log` for the traceback, or run from a terminal:

```sh
love . 2>&1 | tee /tmp/fgd.log
```

### On muOS, the app starts but the display is frozen

muOS's volume OSD daemon sometimes steals the framebuffer.
`mux_launch.sh` suspends it for the session and restores it on exit.
If you launched the app manually, run it through `mux_launch.sh`.

### File listing shows `--` for dates and sizes

The system's `stat` command is not GNU-compatible. `services/fs.lua`
probes for this and falls back to parsing `ls -lan`, which loses the
precise modification timestamp. This is expected on minimal BusyBox
builds.

### Archive operations fail with "tool missing"

The file manager delegates archive handling to system binaries. Check
what is available on your device:

```sh
command -v zip unzip tar 7z
```

On a bare muOS install, `zip` and `tar` are usually present. `7z` is
often not. The app reports the missing tool rather than failing
silently.

### NTP sync fails

`ntpdate` and `sntp` are often absent on handheld builds. The app falls
back to `busybox ntpd -q`. If neither works, set the time from the
**System** screen manually.

### I want to see what the app is doing

Two logs, both persistent:

- `.desktopbase/logs/latest.log` on desktop.
- `data/logs/latest.log` on muOS.

And two runtime logs:

- `data/fgd_runtime.log` — internal errors and warnings.
- `data/fgd_error.log` — global error handler output.

---

## Roadmap

### Shipped in 1.0

- [x] Dual-pane file manager
- [x] Four view modes
- [x] Multi-selection, clipboard
- [x] Archive create and extract
- [x] Trash with restore
- [x] Batch rename
- [x] Checksums
- [x] chmod, symlink
- [x] Disk tools, mounts, NTP
- [x] Text editor
- [x] Image viewer
- [x] Search
- [x] System diagnostics
- [x] Pad test
- [x] Main menu with intro animation
- [x] Boot animation
- [x] muOS glyph

### Planned

- [ ] Plugin loader (`data/plugins/*.lua`)
- [ ] Save file sync between SD1 and SD2
- [ ] FAT32 filename sanitizer
- [ ] Duplicate finder
- [ ] Disk usage treemap
- [ ] Custom keybinding editor

### Explicitly out of scope

- Audio or video playback (muOS ships `mpv`; use it).
- Embedded terminals (SSH from a PC).
- HTTP / SFTP / FTP servers (nobody uses them on a handheld).
- Cloud sync.
- Hex *editing* (read-only hex view only).
- ROM auto-organizers (offer a guided batch rename instead).

---

## License

**GPL-3.0-or-later.** See `LICENSE`.

This project reuses ideas and infrastructure from
[DolphinUI](https://github.com/), the muOS interface layer, and the
LÖVE ecosystem. All third-party code vendored under `vendor/` keeps
its original MIT license; see the individual files for details.

---

## Credits

- **sirpips** aka **SilverCrow2323** — design, code, and stubborn
  refusal to ship a bad UI.
- **SPDW Factory** — the umbrella this tool lives under.
- **The LÖVE team** — for a runtime that fits on a handheld.
- **The muOS community** — for keeping the RG35XX H interesting.

If this tool saves your data, your time, or your sanity, tell somebody
who owns an Anbernic. Word of mouth is the only marketing we can
afford.
# File-Grid-Diver-X-muOS
# File-Grid-Diver-X-muOS
