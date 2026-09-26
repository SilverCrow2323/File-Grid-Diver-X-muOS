# File-GD X -- Plugins

A plugin is a **folder** under `plugins/`.

## Structure

    plugins/
    ├── api.lua           -- permission catalog + sandbox
    ├── loader.lua
    ├── README.md
    └── my_plugin/
        ├── plugin.lua    -- manifest (returns a table)
        └── main.lua      -- entry point (returns a screen table S)

## Manifest

`plugin.lua` must return a table with this shape:

    return {
      name        = "My Plugin",         -- display name
      key         = "my_plugin",          -- unique id
      category    = "Tools",
      version     = "1.0.0",
      author      = "sirpips",
      desc        = "what it does",
      icon        = "eye",                -- icon key for the hub
      colour      = {0.9, 0.6, 0.3},      -- RGB 0..1
      entry       = "main",               -- basename of the entry module
      permissions = {                     -- see "Permissions" below
        "filesystem.read",
      },
    }

## Permissions

Permissions control what a plugin can reach. The app shows a
consent screen the first time a plugin is opened, and stores the
grant in `data/plugin_perms.json`. Nothing is loaded until the user
accepts.

| Permission           | Grants                                                |
|----------------------|-------------------------------------------------------|
| `filesystem.read`    | `io.open("r")`, `io.lines`, `io.read`                 |
| `filesystem.write`   | `io.open("w"/"a")`, `io.write`, `os.remove`, `os.rename` |
| `shell.exec`         | `os.execute`, `io.popen`, `require("core.sh")`        |
| `love.filesystem`    | full `love.filesystem` (read/write the save dir)      |

**Plugins that only use the app's own services do not need any
permission.** `services.fs`, `services.trash`, `ui.*`, `core.*`
(except `core.sh`) are trusted wrappers owned by the app.

When a manifest is updated to ask for more permissions, the consent
screen appears again on the next launch.

Revoke all grants for a plugin by deleting its entry from
`data/plugin_perms.json`, or use `plugins.api.revoke("pkg")`.

## Sandbox

The entry file `main.lua` and any module under `plugins.<your_key>.*`
run inside a sandboxed environment. The sandbox:

- provides a safe base library (`string`, `table`, `math`, `pairs`,
  `ipairs`, `pcall`, `type`, `tostring`, `tonumber`, ...)
- provides the graphics-adjacent `love.*` subset (`graphics`, `timer`,
  `audio`, `math`, `event`, `keyboard`, `mouse`, `window`, `system`)
- routes `print` to `data/fgd_runtime.log` with a `[plugin <pkg>]`
  prefix
- gates `io`, `os.execute`, `io.popen` and `require("core.sh")` behind
  the declared permissions
- lets you `require` any app module (`core.*`, `ui.*`, `services.*`)
  without declaring anything, since those are first-party
- blocks cross-plugin `require`

This is **best-effort**, not a jailbreak-proof sandbox. A plugin that
declares `shell.exec` can do whatever the OS lets it. That's why the
consent screen exists.

## Entry point

`main.lua` returns a **screen table** with the same shape as
anything in `screens/`:

    local S = {}
    function S.enter() end
    function S.leave() end
    function S.update(dt) end
    function S.draw() end
    function S.pad(b) end
    function S.hat(dir) end
    function S.key(k) end
    return S

Optional:
- `S.wants_capture()` + `S.capture_input(kind, value)`
- `S.raw_keys = true`

## That's it

Drop the folder. Restart the app. The plugin appears in the Plugins
hub. The first time you open it you'll see the consent screen.
