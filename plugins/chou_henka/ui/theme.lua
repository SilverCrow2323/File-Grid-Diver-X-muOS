-- ui/theme.lua -- 5 palette temi
local CFG = require("plugins.chou_henka.core.config")
local M = {}
M.THEMES = {
  neon = { id="neon", label="Neon",
    bg={0.020,0.018,0.030}, panel={0.035,0.030,0.055},
    accent={0.95,0.40,0.85}, accent_hi={1.00,0.60,0.95}, accent_lo={0.30,0.15,0.35},
    text={0.95,0.95,0.98}, text_dim={0.55,0.55,0.65},
    ok={0.35,0.90,0.50}, warn={0.95,0.70,0.30}, err={0.95,0.35,0.30} },
  amber = { id="amber", label="Amber",
    bg={0.030,0.020,0.010}, panel={0.055,0.040,0.020},
    accent={0.94,0.66,0.35}, accent_hi={1.00,0.80,0.45}, accent_lo={0.35,0.22,0.10},
    text={0.95,0.92,0.88}, text_dim={0.60,0.55,0.50},
    ok={0.55,0.85,0.45}, warn={0.95,0.75,0.30}, err={0.95,0.40,0.30} },
  green = { id="green", label="Terminal",
    bg={0.010,0.020,0.010}, panel={0.020,0.040,0.020},
    accent={0.40,0.95,0.45}, accent_hi={0.60,1.00,0.65}, accent_lo={0.10,0.30,0.15},
    text={0.85,1.00,0.85}, text_dim={0.45,0.65,0.45},
    ok={0.35,0.95,0.45}, warn={0.95,0.85,0.30}, err={0.95,0.35,0.30} },
  blood = { id="blood", label="Blood",
    bg={0.030,0.010,0.010}, panel={0.055,0.020,0.020},
    accent={0.95,0.30,0.25}, accent_hi={1.00,0.50,0.40}, accent_lo={0.35,0.10,0.08},
    text={0.95,0.90,0.90}, text_dim={0.60,0.50,0.50},
    ok={0.55,0.85,0.45}, warn={0.95,0.70,0.30}, err={1.00,0.20,0.15} },
  mono = { id="mono", label="Mono",
    bg={0.020,0.020,0.020}, panel={0.040,0.040,0.040},
    accent={0.85,0.85,0.85}, accent_hi={1.00,1.00,1.00}, accent_lo={0.30,0.30,0.30},
    text={0.95,0.95,0.95}, text_dim={0.55,0.55,0.55},
    ok={0.70,0.90,0.70}, warn={0.95,0.85,0.50}, err={0.95,0.55,0.55} },
}
M.THEME_ORDER = { "neon","amber","green","blood","mono" }
function M.current()
  local id = CFG.get("ui","theme") or "neon"
  return M.THEMES[id] or M.THEMES.neon
end
function M.set(id) if M.THEMES[id] then CFG.set("ui","theme",id); CFG.save() end end
function M.cycle(dir)
  local cur = CFG.get("ui","theme") or "neon"
  local i = 1; for k,v in ipairs(M.THEME_ORDER) do if v==cur then i=k end end
  i = ((i-1+dir) % #M.THEME_ORDER + #M.THEME_ORDER) % #M.THEME_ORDER + 1
  M.set(M.THEME_ORDER[i]); return M.THEME_ORDER[i]
end
return M
