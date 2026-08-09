local colors = require("colors")
local icons = require("icons")
local settings = require("settings")

-- Spacing from the adjacent widget
sbar.add("item", { width = 5 })

local apple = sbar.add("item", {
  icon = {
    font = { size = 16.0 },
    string = icons.apple,
    padding_right = 8,
    padding_left = 8,
  },
  label = { drawing = false },
  background = {
    color = colors.widget_bg1,
    height = 28,
    corner_radius = 9,
    border_color = colors.bg1,
    border_width = 2,
  },
  padding_left = 1,
  padding_right = 1,
  click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s 0"
})

-- Spacing from the adjacent widget
sbar.add("item", { width = 7 })
