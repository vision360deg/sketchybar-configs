local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local metrics = require("helpers.system_metrics")
local activity_monitor = require("helpers.activity_monitor")

local M = {}

local function usage_color(percent)
  if percent <= 30 then return colors.blue end
  if percent < 60 then return colors.yellow end
  if percent < 80 then return colors.orange end
  return colors.red
end

function M.new(options)
  options = options or {}
  local mode = metrics.widget_mode(options.mode)
  local name = options.name or "widgets.memory"
  local position = options.position or "right"
  local memory_icon = icons.system_monitor and icons.system_monitor.memory or icons.cpu

  local item = sbar.add("graph", name, 42, {
    position = position,
    drawing = options.drawing ~= false,
    updates = true,
    update_freq = 3,
    graph = { color = colors.blue },
    background = { height = 22, color = { alpha = 0 }, border_color = { alpha = 0 }, drawing = true },
    icon = { string = memory_icon },
    label = {
      string = "mem ??%",
      width = 0,
      align = "right",
      y_offset = 7,
      padding_right = 0,
      font = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 9.0 },
    },
    padding_right = settings.paddings + 6,
  })

  item:subscribe("routine", function()
    sbar.exec("/usr/bin/memory_pressure -Q", function(output)
      local fraction, percent = metrics.parse_memory_pressure(output)
      if not fraction then return end
      item:push({ fraction })
      item:set({ graph = { color = usage_color(percent) }, label = "mem " .. percent .. "%" })
    end)
  end)

  local controller = { key = "memory", names = { item.name } }
  function controller.set_visible(visible) item:set({ drawing = visible }) end
  function controller.subscribe(event, callback) item:subscribe(event, callback) end
  function controller.open_activity_monitor() activity_monitor.open("memory") end

  if mode == "single" then
    item:subscribe("mouse.clicked", controller.open_activity_monitor)
    sbar.add("bracket", name .. ".bracket", { item.name }, { background = { color = colors.widget_bg1 } })
    sbar.add("item", name .. ".padding", { position = position, width = settings.group_paddings })
  end

  return controller
end

return M
