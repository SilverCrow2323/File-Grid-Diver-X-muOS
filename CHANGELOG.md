# Changelog

All notable changes to File-GD X are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.4.0] - 2026-09-22

### Added
- **Undo stack** (`services/operations.lua`). Every mutating action
  (rename, batch rename, paste cut, paste copy, trash, mkdir, touch)
  pushes an entry onto a bounded LIFO stack of 50. One Undo reverses
  the last operation, including multi-file operations which count as
  a single entry.
  - Entry points: context menu (X), side panel (START), Ctrl+Z.
- **Per-volume trash** (`services/trash.lua`). Each mount point now
  has its own `.fgd_trash` directory:
  - `/mnt/mmc/foo` → `/mnt/mmc/.fgd_trash/`
  - `/mnt/sdcard/foo` → `/mnt/sdcard/.fgd_trash/`
  - app-internal files → `data/trash/` (fallback)
  Same-volume moves are instant renames. No cross-device copy, no
  doubling of storage requirements, no 4 GB ISO crawling through the
  app's CWD to reach a different filesystem. `list()`, `size()` and
  `purge_all()` now aggregate across every volume.
- **Plugin permissions and sandbox** (`plugins/api.lua`).
  - Permission catalog: `filesystem.read`, `filesystem.write`,
    `shell.exec`, `love.filesystem`.
  - Consent screen appears the first time a plugin asks for a
    permission it has not been granted. Grants persist to
    `data/plugin_perms.json`.
  - Manifests that do not request permissions are still loaded
    sandboxed: `io`, `os.execute`, `io.popen` and `require("core.sh")`
    are gated; cross-plugin `require` is blocked; `print` is routed to
    `data/fgd_runtime.log` with a `[plugin <pkg>]` prefix.
  - Existing plugins were pre-granted so nothing breaks on first run.
- **Native bindings layer** (`core/native.lua`, `core/lfs.lua`).
  - `package.cpath` is extended to `lib/<arch>/` at boot.
  - `services/fs.lua` tries native `lfs` for `list`, `stat`, `is_dir`,
    `exists`, `mkdir`, `touch` before falling back to shell.
  - `core/json.lua` tries native `cjson` for encode/decode before
    falling back to the pure-Lua implementation.
  - `tools/build_native.sh` cross-compiles `lfs.so` and `cjson.so`
    for `host` or `aarch64`.
  - Boot log line `[native] arch=... lfs=... cjson=...` makes the
    state visible.
- **Test suite and CI**.
  - `tests/json_spec.lua`, `tests/fs_spec.lua`,
    `tests/operations_spec.lua`, `tests/settings_store_spec.lua`.
  - `.busted`, `.luacheckrc` configurations.
  - `tools/run_tests.sh` local runner.
  - `.github/workflows/ci.yml` with three jobs: `lint` (luacheck),
    `test` (busted, pure-Lua path), `test-native` (busted with
    luafilesystem and lua-cjson installed).
  - README `## Testing` section documenting how to run everything.
- **`.editorconfig`** for consistent style across editors.

### Changed
- **`screens/grid.lua`** — `do_delete` now respects `dev.use_trash`
  (default ON) so deletes go to the trash and can be undone. Hard
  delete only used if the toggle is off. Context menu gained
  "Undo last" at the top. Side panel gained "Undo last" in the edit
  group. Ctrl+Z is a global undo hotkey.
- **`screens/storage.lua` CLEANUP section** uses `Trash.purge_all()`
  and `Trash.size()` so the reported size is the real total across
  every volume, and WIPE also removes hidden files.
- **`core/json.lua`** header documents the native fast path.
- **`plugins/README.md`** rewritten to document the permission model
  and the sandbox in full.

### Fixed
- **Plugin permission gap** — a plugin could previously `require`
  `core.sh` and run any shell command without any user-visible
  declaration. Now gated and consented.
- **Trash on wrong volume** — moving a large file from `/mnt/sdcard`
  to the central `data/trash` on a different filesystem required a
  full copy and doubled the temporary storage requirement. Now
  renamed in place.

### Notes
- Plugins that use only first-party services (`services.fs`,
  `services.trash`, `ui.*`, `core.*`) do not need any permission.
  Those wrappers belong to the app and are trusted.
- The sandbox is best-effort, not jailbreak-proof. A plugin that
  declares `shell.exec` can do whatever the OS lets it. That is why
  the consent screen exists.
- To revoke a plugin's grants, delete its entry from
  `data/plugin_perms.json`, or call `plugins.api.revoke("pkg")` from
  a Lua console.



## [1.3.0] - 2026-09-21

### Added
- **Unified STORAGE screen** (`screens/storage.lua`), a four-section hub:
  - **VOLUMES** — mount list with free/total bars, remount actions.
  - **ANALYZE** — per-category disk usage scan (ROM / VIDEO / AUDIO /
    IMAGE / ARCHIVE / OTHER) with a recoverable-space summary.
  - **DUPLICATES** — content-hash (md5) duplicate finder, size
    pre-filter, per-group keep/drop toggles, move-to-trash apply.
  - **CLEANUP** — one-tap wipe for trash, logs, downloads, tmp,
    snapshots.
  All four sections share the same rail+panel layout, per-section
  accent colour, and cyan mecha frame.
- **GRID-DEV full-screen console** (`screens/grid_dev.lua`), reached
  from Settings. Five core categories (PERFORMANCE, DEBUG/DIAG,
  SYSTEM BEHAVIOR, WIRE/NETWORK, MAINTENANCE) plus a GOKU SSJ4
  personalisation category. Row kinds: bool, enum, num, action, info.
- **Goku SSJ4 mascot** — floating sprite in the GRID-DEV rail, fully
  configurable (show/hide, left/right, size, float amplitude, float
  speed, ground shadow). Avatar `gokuavatarssj4.png` in the panel
  header when the category is selected.
- **Background music system** — `play_bgm` / `fade_bgm` / `stop_bgm` /
  `update_bgm` in `core/audio.lua`. Streamed OGG with static WAV
  fallback. The Final Bout graphic now starts `finalbout_griddev.ogg`
  together with `finalbout.wav` and fades it out over 2 s when the
  graphic ends.
- **OGG-first SFX loader** — every sound tries `.ogg` then `.wav`; the
  loader reports which extension was used and lists any missing files.
- **Dev unlock is session-only by default.** The Konami code sets an
  in-memory flag; the previous JSON key (`ui.dev_unlocked`) is migrated
  and removed. A new `dev.persist_unlock` toggle inside GRID-DEV >
  MAINTENANCE keeps the unlock across sessions if the user wants it.
  A toast after the Konami code points the user to Settings > GRID-DEV.
- **Doppel-Defier v2.0.0** — real content-based duplicate finder:
  - Pass 1: `find` lists every file with its size.
  - Pass 2: only same-size candidates are hashed with `md5sum`.
  - Groups are formed by `(size, hash)` so unrelated files with
    similar names never land in the same group.
- **`.editorconfig`** for consistent style across editors.

### Changed
- **`screens/settings.lua`** — the monolithic GRID-DEV block was
  removed. Settings now shows a single GRID-DEV row in mecha style
  that opens the full-screen console. `rebuild()`,
  `selectable_indices()`, `current_entry()`, `height_of()` all
  simplified accordingly.
- **Side panel in `screens/grid.lua`** — the "Disk tools" entry was
  replaced by "Storage", pointing to the unified hub.
- **`plugins/storage_peeper`** and **`plugins/doppel_defier`** are now
  thin redirect screens. They explain the move and offer a one-press
  jump into STORAGE.
- **`data/fgd.json`** is written pretty-printed (2-space indent)
  instead of a single 539-char line.
- **`screens/grid.lua`** no longer writes a debug line to
  `data/grid_events.log` on every button press.
- **`disk_tools.lua`** is unchanged and still loadable from code, but
  is no longer reachable from the UI. Superseded by STORAGE > VOLUMES.

### Fixed
- **`ui/finalbout.lua`** — `M.active` was accessed without a nil guard
  in `love.gamepadpressed`, `love.keypressed`, `love.update` and
  `love.draw`. Now guarded, no crash if the module fails to load.
- **Audio settings toggles** — the Settings screen was flipping
  `sound.enabled` and `sound.volume` in JSON but never calling into
  `core/audio`. Now they call `SFX.set_enabled()` and
  `SFX.set_volume()`.
- **Root detection in plugins** — `FS.is_dir()` was called up to four
  times per frame per plugin (240 forks/sec while idle). Now cached
  with a 5 s TTL.
- **Downloader size fallback** — the progress poller used
  `stat -c %s` (GNU) or `stat -f %z` (BSD). Both fail on BusyBox.
  Falls back to `wc -c < "$FILE"`.
- **Downloader URL** — quoted with `sh.shq()` before being passed to
  `curl -sIL`.

### Removed
- **`.desktopbase/.fgd_backup_*` debris** — stale snapshot directories
  removed.
- **Dead debug logging** in `screens/grid.lua` (`data/grid_events.log`).
- **Unused FS import** in `plugins/doppel_defier/dupes.lua`.

### Migration notes
- If you had `ui.dev_unlocked = true` in `data/fgd.json`, it is cleared
  once at the first launch of 1.3.0 and never written again.
- To keep the dev menu unlocked between sessions, go to
  GRID-DEV > MAINTENANCE and enable "Persist dev unlock across sessions".
- The Konami sequence is unchanged:
  RIGHT, LEFT, DOWN, UP, RIGHT, LEFT, DOWN, UP, START on the main menu.

## [1.2.0] - 2026-09-21

Early release. 
## [1.1.10] - 2026-09-21

Early release. 
## [1.1.0] - 2026-09-21

First multi-plugin build.

## [1.0.0] - 2026-09-21

Initial packaged release. 
