local active_border = { colors = { "rgba(1769d2cc)", "rgba(7651b599)" }, angle = 45 }
local inactive_border = "rgba(20242b1a)"

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
    inactive_opacity = 0.98,
    shadow = {
      enabled = true,
      range = 18,
      render_power = 3,
      color = "rgba(1b253442)",
      color_inactive = "rgba(1b253426)",
    },
    blur = {
      enabled = true,
      size = 8,
      passes = 2,
      vibrancy = 0.12,
      popups = true,
    },
  },
})
