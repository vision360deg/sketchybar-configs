local colors = require("colors")
local settings = require("settings")

local menu_watcher = sbar.add("item", {
  drawing = false,
  updates = true,
})
sbar.add("event", "swap_menus_and_spaces")

local max_items = 15
local menu_items = {}
local menu_count = 0
local visible = false

for index = 1, max_items do
  local menu = sbar.add("item", "menu." .. index, {
    padding_left = settings.paddings,
    padding_right = settings.paddings,
    drawing = false,
    icon = { drawing = false },
    label = {
      font = {
        style = settings.font.style_map[index == 1 and "Heavy" or "Semibold"]
      },
      padding_left = 6,
      padding_right = 6,
    },
    click_script = "$CONFIG_DIR/helpers/menus/bin/menus -s " .. index,
  })

  menu_items[index] = menu
end

sbar.add("bracket", { '/menu\\..*/' }, {
  background = { color = colors.bg1 }
})

local menu_padding = sbar.add("item", "menu.padding", {
  drawing = false,
  width = 5,
})

local function set_visible(next_visible)
  visible = next_visible
  sbar.set('/menu\\..*/', { drawing = false })

  if visible then
    for index = 1, menu_count do
      menu_items[index]:set({ drawing = true })
    end
  end

  menu_padding:set({ drawing = visible and menu_count > 0 })
end

local function update_menus()
  sbar.exec("$CONFIG_DIR/helpers/menus/bin/menus -l", function(menus)
    sbar.set('/menu\\..*/', { drawing = false })
    menu_count = 0

    for menu in string.gmatch(menus, '[^\r\n]+') do
      if menu_count >= max_items - 1 then break end
      menu_count = menu_count + 1
      menu_items[menu_count]:set({
        label = menu,
        drawing = visible,
      })
    end

    menu_padding:set({ drawing = visible and menu_count > 0 })
  end)
end

menu_watcher:subscribe("front_app_switched", update_menus)
update_menus()

return {
  show = function()
    set_visible(true)
  end,
  hide = function()
    set_visible(false)
  end,
  refresh = update_menus,
}
