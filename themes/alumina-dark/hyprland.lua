local active_border = "rgba(72a7ffdd) rgba(b69cffbb) 45deg"
local inactive_border = "rgba(ffffff16)"

hl.config({
  general = {
    gaps_in = 6,
    gaps_out = 10,
    border_size = 1,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },

  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },

  decoration = {
    rounding = 12,
    rounding_power = 4.0,
    active_opacity = 1.0,
    inactive_opacity = 0.97,
    shadow = {
      enabled = true,
      range = 18,
      render_power = 3,
      color = "rgba(00000066)",
      color_inactive = "rgba(0000003d)",
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      vibrancy = 0.15,
      popups = true,
    },
  },
})
