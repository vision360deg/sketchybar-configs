local colors = require("colors")

-- Equivalent to the --bar domain
sbar.bar({
  height = 28,
  color = colors.bg2,
  padding_right = 2,
  padding_left = 2,
  margin = 4,
  corner_radius = 5,
  y_offset = 2,
  topmost = "window",
  hidden = "all"
})
