return {
  name        = "Chou Henka Media Center",
  key         = "chou_henka",
  category    = "Media",
  version     = "2.1.0",
  author      = "sirpips",
  desc        = "Mini media center: libraries, player, themes, addons",
  icon        = "media",
  colour      = {0.95, 0.40, 0.85},
  entry       = "main",
  permissions = { "filesystem.read", "filesystem.write", "shell.exec" },
  capabilities = {
    libraries = true, themes = true, addons = true, player_engines = true,
  },
}
