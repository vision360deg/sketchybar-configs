local settings = require("settings")

local display_capacity = 8
local items = {}

for display_index = 1, display_capacity do
  local item = sbar.add("item", "front_app." .. display_index, {
    display = display_index,
    icon = { drawing = false },
    label = {
      font = {
        style = settings.font.style_map["Black"],
        size = 12.0,
      },
    },
    updates = true,
  })

  item:subscribe("mouse.clicked", function(_)
    sbar.trigger("swap_menus_and_spaces")
  end)

  items[display_index] = item
end

local front_app = {
  items = items,
}

function front_app.set_app(display_index, app)
  local item = items[display_index]
  if not item or not app or app == "" then return end
  item:set({ label = { string = app } })
end

function front_app.set_visible(visible)
  for _, item in pairs(items) do
    item:set({ drawing = visible })
  end
end

return front_app
