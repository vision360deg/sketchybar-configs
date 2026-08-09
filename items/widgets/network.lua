local icons = require("icons")
local colors = require("colors")
local settings = require("settings")
local metrics = require("helpers.system_metrics")
local activity_monitor = require("helpers.activity_monitor")

local M = {}

local function graph_background(height, y_offset)
  return {
    height = height,
    y_offset = y_offset,
    color = { alpha = 0 },
    border_color = { alpha = 0 },
    drawing = true,
  }
end

function M.new(options)
  options = options or {}
  local mode = metrics.widget_mode(options.mode)
  local name = options.name or "widgets.network"
  local position = options.position or "right"
  local drawing = options.drawing ~= false
  local peak = 1
  local ratio_samples = {}
  local ratio_in_total = 0
  local ratio_out_total = 0

  metrics.start_network_provider()

  local outbound = sbar.add("graph", name .. ".packets_out", 52, {
    position = position,
    drawing = drawing,
    updates = true,
    y_offset = -3,
    width = 0,
    padding_left = 0,
    padding_right = settings.paddings + 6,
    graph = {
      color = colors.red,
      fill_color = colors.with_alpha(colors.red, 0.18),
    },
    background = graph_background(22, 0),
    icon = {
      string = icons.wifi.bidirectional,
      padding_left = 5,
      padding_right = 4,
      y_offset = 3,
      font = { style = settings.font.style_map["Bold"], size = 13.0 },
    },
    label = { drawing = false },
  })

  local lower_mask = sbar.add("graph", name .. ".lower_mask", 52, {
    position = position,
    drawing = drawing,
    y_offset = -3,
    width = 0,
    padding_left = 0,
    padding_right = settings.paddings + 6,
    graph = {
      color = colors.transparent,
      fill_color = colors.widget_bg1,
    },
    background = graph_background(22, 0),
    icon = { drawing = false },
    label = { drawing = false },
  })

  local inbound_fill = sbar.add("graph", name .. ".packets_in_fill", 52, {
    position = position,
    drawing = drawing,
    y_offset = -3,
    width = 0,
    padding_left = 0,
    padding_right = settings.paddings + 6,
    graph = {
      color = colors.transparent,
      fill_color = colors.with_alpha(colors.blue, 0.18),
    },
    background = graph_background(22, 0),
    icon = { drawing = false },
    label = { drawing = false },
  })

  local baseline = sbar.add("graph", name .. ".baseline", 52, {
    position = position,
    drawing = drawing,
    y_offset = -3,
    width = 0,
    padding_left = 0,
    padding_right = settings.paddings + 6,
    graph = {
      color = colors.grey,
      fill_color = colors.transparent,
      line_width = 1,
    },
    background = graph_background(22, 0),
    icon = { drawing = false },
    label = {
      string = "pkt ??:??",
      width = 0,
      align = "right",
      y_offset = 10,
      padding_right = 0,
      font = {
        family = settings.font.numbers,
        style = settings.font.style_map["Bold"],
        size = 9.0,
      },
    },
  })

  for _ = 1, 52 do
    lower_mask:push({ 0.5 })
    inbound_fill:push({ 0.5 })
    baseline:push({ 0.5 })
  end

  local inbound = sbar.add("graph", name .. ".packets_in", 52, {
    position = position,
    drawing = drawing,
    y_offset = -3,
    updates = true,
    padding_left = 0,
    padding_right = settings.paddings + 6,
    graph = {
      color = colors.blue,
      fill_color = colors.widget_bg1,
    },
    background = graph_background(22, 0),
    icon = { drawing = false },
    label = { drawing = false },
  })

  for _ = 1, 52 do
    outbound:push({ 0.5 })
    inbound:push({ 0.5 })
  end

  outbound:subscribe("network_update", function(env)
    local raw_packets_in = math.max(tonumber(env.packets_in) or 0, 0)
    local raw_packets_out = math.max(tonumber(env.packets_out) or 0, 0)
    table.insert(ratio_samples, { raw_packets_in, raw_packets_out })
    ratio_in_total = ratio_in_total + raw_packets_in
    ratio_out_total = ratio_out_total + raw_packets_out

    if #ratio_samples > 3 then
      local expired = table.remove(ratio_samples, 1)
      ratio_in_total = ratio_in_total - expired[1]
      ratio_out_total = ratio_out_total - expired[2]
    end

    local inbound_share, outbound_share = metrics.packet_ratio(ratio_in_total, ratio_out_total)
    local packets_in, packets_out
    packets_in, packets_out, peak = metrics.normalize_packet_rates(raw_packets_in, raw_packets_out, peak)
    outbound:push({ 0.5 + packets_out * 0.5 })
    inbound:push({ 0.5 - packets_in * 0.5 })
    baseline:set({ label = string.format("pkt %d:%d", inbound_share, outbound_share) })
  end)

  local items = { outbound, lower_mask, inbound_fill, baseline, inbound }
  local controller = {
    key = "network",
    names = { outbound.name, lower_mask.name, inbound_fill.name, baseline.name, inbound.name },
  }

  function controller.set_visible(visible)
    for _, item in ipairs(items) do
      item:set({ drawing = visible })
    end
  end

  function controller.subscribe(event, callback)
    for _, item in ipairs(items) do
      item:subscribe(event, callback)
    end
  end

  function controller.open_activity_monitor()
    activity_monitor.open("network")
  end

  if mode == "single" then
    controller.subscribe("mouse.clicked", controller.open_activity_monitor)
    sbar.add("bracket", name .. ".bracket", controller.names, {
      background = { color = colors.widget_bg1 },
    })
    sbar.add("item", name .. ".padding", {
      position = position,
      width = settings.group_paddings,
    })
  end

  return controller
end

return M
