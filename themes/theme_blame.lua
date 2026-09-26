-- Blame!-style: near-black warm background, rust/amber terminals,
-- cold cyan readouts, bone-white text. Everything is industrial.
return {
  id   = "blame",
  name = "Blame!",

  -- Base
  bg           = {0.024, 0.020, 0.016},
  bg_fog       = {0.045, 0.038, 0.030},
  structure    = {0.098, 0.085, 0.070},
  structure_hi = {0.176, 0.155, 0.128},
  structure_lo = {0.056, 0.048, 0.040},
  grid_faint   = {0.140, 0.122, 0.100},
  grid_dim     = {0.196, 0.172, 0.140},

  -- Panels
  panel        = {0.055, 0.048, 0.040},
  panel_alt    = {0.075, 0.065, 0.055},
  panel_hi     = {0.098, 0.085, 0.070},

  -- Text
  text         = {0.850, 0.820, 0.760},
  text_dim     = {0.440, 0.420, 0.380},
  text_dark    = {0.290, 0.270, 0.250},
  text_bright  = {0.960, 0.940, 0.900},

  -- Accents
  amber        = {0.830, 0.540, 0.240},
  amber_hi     = {0.940, 0.660, 0.350},
  amber_lo     = {0.350, 0.220, 0.100},
  cyan         = {0.290, 0.620, 0.720},
  cyan_hi      = {0.480, 0.800, 0.900},
  green        = {0.420, 0.600, 0.350},
  red          = {0.660, 0.200, 0.160},
  red_hi       = {0.900, 0.300, 0.250},

  -- Semantic aliases used by generic UI code
  accent   = {0.940, 0.660, 0.350},
  focus    = {0.940, 0.660, 0.350},
  card_bg  = {0.055, 0.048, 0.040},
  card_border = {0.196, 0.172, 0.140},

  -- Rendering hints
  outline_boost = 1.0,
  grid_mirror   = false,
  crt_scanlines = true,
  static_noise  = true,
  vignette      = 0.60,
}
