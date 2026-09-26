return {
  name     = "Disk Doctor",
  key      = "disk_doctor",
  category = "Diagnostics",
  version  = "1.0.0",
  author   = "sirpips",
  desc     = "guided wizard to free up disk space",
  icon     = "gear",
  colour   = {0.30, 0.85, 0.95},
  entry    = "main",
  priority = 20,
  permissions = {
    "filesystem.read",
    "filesystem.write",
    "shell.exec",
  },
}
