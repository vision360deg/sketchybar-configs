local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local metrics = require("helpers.system_metrics")
local activity_monitor = require("helpers.activity_monitor")
local popup_manager = require("helpers.popup_manager")

local metric_order = { "cpu", "memory", "energy", "disk", "network" }
local metric_labels = {
  cpu = "CPU",
  memory = "Memory",
  energy = "Energy",
  disk = "Disk",
  network = "Network",
}

local constructors = {
  cpu = require("items.widgets.cpu"),
  memory = require("items.widgets.memory"),
  energy = require("items.widgets.energy"),
  disk = require("items.widgets.disk"),
  network = require("items.widgets.network"),
}

local selected_key = "cpu"
local controllers = {}
local names = {}
local popup_items = {}

for _, key in ipairs(metric_order) do
  local controller = constructors[key].new({
    mode = "embedded",
    name = "widgets.system_monitor." .. key,
    position = "right",
    drawing = key == selected_key,
  })
  controllers[key] = controller
  for _, name in ipairs(controller.names) do
    table.insert(names, name)
  end
end

local bracket = sbar.add("bracket", "widgets.system_monitor.bracket", names, {
  background = { color = colors.bg1 },
  popup = { align = "center" },
})

sbar.add("item", "widgets.system_monitor.padding", {
  position = "right",
  width = settings.group_paddings,
})

local function update_popup_colors()
  for key, item in pairs(popup_items) do
    item:set({
      label = { color = key == selected_key and colors.white or colors.grey },
    })
  end
end

local function persist(key)
  sbar.exec("defaults write com.federico.sketchybar system_monitor_metric -string " .. key)
end

local function select_metric(key, should_persist)
  if not metrics.valid_metric(key) then key = "cpu" end

  controllers[selected_key].set_visible(false)
  selected_key = key
  controllers[selected_key].set_visible(true)
  update_popup_colors()

  if should_persist then persist(key) end
  bracket:set({ popup = { drawing = false } })
end

local function hide_popup()
  bracket:set({ popup = { drawing = false } })
end

local function toggle_popup()
  bracket:set({ popup = { drawing = "toggle" } })
end

for _, key in ipairs(metric_order) do
  controllers[key].subscribe("mouse.clicked", toggle_popup)

  local icon_width = 30
  local popup_icon = {
    string = key == "network" and icons.wifi.up_down or icons.system_monitor[key],
    width = icon_width,
    align = "center",
  }

  local popup_item = sbar.add("item", "widgets.system_monitor.popup." .. key, {
    position = "popup." .. bracket.name,
    width = 180,
    icon = popup_icon,
    label = {
      string = metric_labels[key],
      width = 160 - icon_width,
      align = "left",
      color = colors.grey,
    },
  })

  popup_item:subscribe("mouse.clicked", function()
    select_metric(key, true)
  end)
  popup_items[key] = popup_item
end

local open_item = sbar.add("item", "widgets.system_monitor.popup.activity_monitor", {
  position = "popup." .. bracket.name,
  width = 180,
  background = {
    height = 2,
    color = colors.grey,
    y_offset = 14
  },
  icon = {
    string = icons.system_monitor.activity_monitor,
    width = 30,
    align = "center",
  },
  label = {
    string = "Open Activity Monitor",
    width = 130,
    align = "left",
  },
})

open_item:subscribe("mouse.clicked", function()
  bracket:set({ popup = { drawing = false } })
  activity_monitor.open(selected_key)
end)

popup_manager.register(bracket, function()
  local items = {}
  for _, key in ipairs(metric_order) do table.insert(items, popup_items[key]) end
  table.insert(items, open_item)
  return items
end, hide_popup)

update_popup_colors()

sbar.exec("defaults read com.federico.sketchybar system_monitor_metric 2>/dev/null", function(output)
  local stored = output:match("^%s*(.-)%s*$")
  select_metric(metrics.valid_metric(stored) and stored or "cpu", false)
end)

return {
  select_metric = select_metric,
}
