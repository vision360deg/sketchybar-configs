local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local metrics = require("helpers.system_metrics")
local activity_monitor = require("helpers.activity_monitor")

local M = {}

local function load_color(load)
  if load <= 30 then return colors.blue end
  if load < 60 then return colors.yellow end
  if load < 80 then return colors.orange end
  return colors.red
end

function M.new(options)
  options = options or {}
  local mode = metrics.widget_mode(options.mode)
  local name = options.name or "widgets.cpu"
  local position = options.position or "right"
  local drawing = options.drawing ~= false
  local cpu_icon = icons.system_monitor and icons.system_monitor.cpu or icons.cpu

  metrics.start_cpu_provider()

  local cpu = sbar.add("graph", name, 42, {
    position = position,
    drawing = drawing,
    updates = true,
    graph = { color = colors.blue },
    background = {
      height = 22,
      color = { alpha = 0 },
      border_color = { alpha = 0 },
      drawing = true,
    },
    icon = { string = cpu_icon },
    label = {
      string = "cpu ??%",
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
      align = "right",
      padding_right = 0,
      width = 0,
      y_offset = 7,
    },
    padding_right = settings.paddings + 6,
  })

  cpu:subscribe("cpu_update", function(env)
    local load = tonumber(env.total_load)
    if not load then return end

    cpu:push({ load / 100 })
    cpu:set({
      graph = { color = load_color(load) },
      label = "cpu " .. load .. "%",
    })
  end)

  local controller = {
    key = "cpu",
    names = { cpu.name },
  }

  function controller.set_visible(visible)
    cpu:set({ drawing = visible })
  end

  function controller.subscribe(event, callback)
    cpu:subscribe(event, callback)
  end

  function controller.open_activity_monitor()
    activity_monitor.open("cpu")
  end

  if mode == "single" then
    cpu:subscribe("mouse.clicked", controller.open_activity_monitor)
    sbar.add("bracket", name .. ".bracket", { cpu.name }, {
      background = { color = colors.bg1 },
    })
    sbar.add("item", name .. ".padding", {
      position = position,
      width = settings.group_paddings,
    })
  end

  return controller
end

return M
