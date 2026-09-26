return {
  name     = "Chou Henka",
  key      = "chou_henka",
  category = "Media",
  version  = "2.0.0",
  author   = "sirpips",
  desc     = "media center: library, player, EQ, visualizer, video",
  icon     = "wave",
  colour   = {0.95, 0.40, 0.85},
  entry    = "main",
  priority = 3,
  extender = true,
  extensions = {
    "mp3", "ogg", "oga", "wav", "flac", "opus", "m4a", "aac",
    "wma", "ape", "alac",
    "mp4", "mkv", "avi", "webm", "mov", "mpg", "mpeg", "m4v",
    "flv", "wmv", "3gp", "ogv", "ts", "m2ts", "vob",
  },
  permissions = {
    "filesystem.read",
    "filesystem.write",
    "shell.exec",
  },
}
