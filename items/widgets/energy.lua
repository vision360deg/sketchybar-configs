local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local metrics = require("helpers.system_metrics")
local activity_monitor = require("helpers.activity_monitor")

local M = {}

function M.new(options)
  options = options or {}
  local mode = metrics.widget_mode(options.mode)
  local name = options.name or "widgets.energy"
  local position = options.position or "right"
  local energy_icon = icons.system_monitor and icons.system_monitor.energy or icons.cpu
  local peak = 1

  local item = sbar.add("graph", name, 42, {
    position = position,
    drawing = options.drawing ~= false,
    updates = true,
    update_freq = 5,
    graph = { color = colors.green },
    background = { height = 22, color = { alpha = 0 }, border_color = { alpha = 0 }, drawing = true },
    icon = { string = energy_icon },
    label = {
      string = "nrg ??",
      width = 0,
      align = "right",
      y_offset = 7,
      padding_right = 0,
      font = { family = settings.font.numbers, style = settings.font.style_map["Bold"], size = 9.0 },
    },
    padding_right = settings.paddings + 6,
  })

  item:subscribe("routine", function()
    sbar.exec("/usr/bin/top -l 2 -n 9999 -stats power", function(output)
      local score = metrics.parse_energy_scores(output)
      if not score then return end
      local normalized
      normalized, peak = metrics.normalize_energy(score, peak)
      item:push({ normalized })
      item:set({ label = "nrg " .. math.floor(score + 0.5) })
    end)
  end)

  local controller = { key = "energy", names = { item.name } }
  function controller.set_visible(visible) item:set({ drawing = visible }) end
  function controller.subscribe(event, callback) item:subscribe(event, callback) end
  function controller.open_activity_monitor() activity_monitor.open("energy") end

  if mode == "single" then
    item:subscribe("mouse.clicked", controller.open_activity_monitor)
    sbar.add("bracket", name .. ".bracket", { item.name }, { background = { color = colors.bg1 } })
    sbar.add("item", name .. ".padding", { position = position, width = settings.group_paddings })
  end

  return controller
end

return M
