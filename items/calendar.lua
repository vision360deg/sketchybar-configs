local settings = require("settings")
local colors = require("colors")

-- Spacing from the adjacent right-side widget
sbar.add("item", { position = "right", width = settings.group_paddings })

local cal = sbar.add("item", {
  icon = {
    color = colors.white,
    padding_left = 8,
    font = {
      style = settings.font.style_map["Black"],
      size = 12.0,
    },
  },
  label = {
    color = colors.white,
    padding_right = 8,
    width = 49,
    align = "right",
    font = { family = settings.font.numbers },
  },
  position = "right",
  update_freq = 30,
  padding_left = 1,
  padding_right = 1,
  background = {
    color = colors.widget_bg1,
    height = 28,
    corner_radius = 9,
    border_color = colors.bg2,
    border_width = 2,
    image = {
      corner_radius = 9,
      border_color = colors.grey,
      border_width = 1,
    },
  },
  click_script = "open -a 'Calendar'"
})

-- Spacing from the adjacent right-side widget
sbar.add("item", { position = "right", width = settings.group_paddings })

cal:subscribe({ "forced", "routine", "system_woke" }, function(env)
  cal:set({ icon = os.date("%a. %d %b."), label = os.date("%H:%M") })
end)
