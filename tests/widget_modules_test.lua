package.path = "./?.lua;./?/init.lua;" .. package.path

local added = {}
local addition_order = {}
local executed = {}

local function new_item(name)
  local item = {
    name = name,
    subscriptions = {},
    sets = {},
    pushes = {},
  }

  function item:subscribe(event, callback)
    self.subscriptions[event] = callback
  end

  function item:set(value)
    table.insert(self.sets, value)
  end

  function item:push(value)
    table.insert(self.pushes, value)
  end

  return item
end

local anonymous_index = 0
_G.sbar = {
  add = function(kind, name, third, fourth)
    local options
    if type(name) == "table" then
      anonymous_index = anonymous_index + 1
      options = name
      name = "anonymous." .. anonymous_index
    elseif fourth ~= nil then
      options = fourth
    else
      options = third
    end

    local item = new_item(name)
    added[name] = { kind = kind, item = item, options = options, component_size = fourth ~= nil and third or nil }
    table.insert(addition_order, name)
    return item
  end,
  exec = function(command)
    table.insert(executed, command)
  end,
}

local cpu_module = require("items.widgets.cpu")
assert(type(cpu_module.new) == "function", "CPU module exports new(options)")

local embedded = cpu_module.new({ mode = "embedded", name = "test.cpu.embedded", drawing = false })
assert(embedded.key == "cpu", "CPU controller key")
assert(#embedded.names == 1 and embedded.names[1] == "test.cpu.embedded", "CPU controller names")
assert(added["test.cpu.embedded.bracket"] == nil, "embedded CPU omits bracket")
assert(added["test.cpu.embedded.padding"] == nil, "embedded CPU omits padding")
assert(added["test.cpu.embedded"].item.subscriptions["mouse.clicked"] == nil, "embedded CPU omits standalone click")
assert(added["test.cpu.embedded"].options.updates == true, "embedded CPU updates while hidden")

local single = cpu_module.new({ name = "test.cpu.single" })
assert(added["test.cpu.single.bracket"], "single CPU adds bracket")
assert(added["test.cpu.single.padding"], "single CPU adds padding")
assert(added["test.cpu.single"].item.subscriptions["mouse.clicked"], "single CPU adds click")

local click_called = false
embedded.subscribe("mouse.clicked", function() click_called = true end)
added["test.cpu.embedded"].item.subscriptions["mouse.clicked"]()
assert(click_called, "controller subscribe forwards events")

embedded.set_visible(true)
assert(#added["test.cpu.embedded"].item.sets == 1, "controller visibility updates item")
assert(#executed == 1, "CPU provider starts only once")

print("widget module tests passed")

local expected_metric_labels = {
  memory = "mem ??%",
  disk = "dsk ??%",
  energy = "nrg ??",
}

for _, key in ipairs({ "memory", "disk", "energy" }) do
  local module = require("items.widgets." .. key)
  assert(type(module.new) == "function", key .. " module exports new(options)")

  local embedded_name = "test." .. key .. ".embedded"
  local embedded_widget = module.new({ mode = "embedded", name = embedded_name, drawing = false })
  assert(embedded_widget.key == key, key .. " controller key")
  assert(#embedded_widget.names == 1 and embedded_widget.names[1] == embedded_name, key .. " controller names")
  assert(added[embedded_name .. ".bracket"] == nil, key .. " embedded omits bracket")
  assert(added[embedded_name].item.subscriptions["routine"], key .. " subscribes to routine updates")
  assert(added[embedded_name].options.updates == true, key .. " updates while hidden")
  assert(added[embedded_name].options.background.height == 22, key .. " graph canvas height")
  assert(added[embedded_name].options.background.drawing == true, key .. " graph canvas enables vertical padding")
  assert(added[embedded_name].options.label.align == "right", key .. " zero-width label remains visible")
  assert(added[embedded_name].options.label.string == expected_metric_labels[key], key .. " abbreviated label")

  local single_name = "test." .. key .. ".single"
  module.new({ name = single_name })
  assert(added[single_name .. ".bracket"], key .. " single adds bracket")
  assert(added[single_name .. ".padding"], key .. " single adds padding")
  assert(added[single_name].item.subscriptions["mouse.clicked"], key .. " single adds click")
end

local energy_routine = added["test.energy.embedded"].item.subscriptions["routine"]
energy_routine()
assert(executed[#executed]:find("top %-l 2"), "Energy samples two top intervals")

print("command-backed widget tests passed")

local network_module = require("items.widgets.network")
assert(type(network_module.new) == "function", "Network module exports new(options)")

local configured_colors = require("colors")
local configured_icons = require("icons")
local configured_settings = require("settings")
assert(configured_icons.wifi.bidirectional == "􀑹", "Network bar uses the single combined up-down glyph")
assert(configured_icons.wifi.up_down == "􀄬", "Network popup keeps its previous stacked arrow glyph")
local embedded_network = network_module.new({ mode = "embedded", name = "test.network.embedded", drawing = false })
assert(embedded_network.key == "network", "Network controller key")
assert(#embedded_network.names == 5, "Network controller owns packet, fill, mask, and baseline graphs")
assert(embedded_network.names[1] == "test.network.embedded.packets_out", "Network owns upper outbound graph")
assert(embedded_network.names[2] == "test.network.embedded.lower_mask", "Network owns lower-half mask")
assert(embedded_network.names[3] == "test.network.embedded.packets_in_fill", "Network owns inbound fill graph")
assert(embedded_network.names[4] == "test.network.embedded.baseline", "Network owns center baseline")
assert(embedded_network.names[5] == "test.network.embedded.packets_in", "Network owns lower inbound graph")
assert(added["test.network.embedded.bracket"] == nil, "embedded Network omits bracket")

local outbound = added["test.network.embedded.packets_out"]
local lower_mask = added["test.network.embedded.lower_mask"]
local inbound_fill = added["test.network.embedded.packets_in_fill"]
local baseline = added["test.network.embedded.baseline"]
local inbound = added["test.network.embedded.packets_in"]
local network_creation = {}
for index, item_name in ipairs(addition_order) do
  network_creation[item_name] = index
end
assert(network_creation[outbound.item.name] < network_creation[lower_mask.item.name], "outbound graph is below lower-half mask")
assert(network_creation[lower_mask.item.name] < network_creation[inbound_fill.item.name], "lower-half mask is below inbound fill")
assert(network_creation[inbound_fill.item.name] < network_creation[baseline.item.name], "inbound fill is below baseline")
assert(network_creation[baseline.item.name] < network_creation[inbound.item.name], "baseline is below width-bearing inbound graph")
assert(inbound.kind == "graph" and outbound.kind == "graph", "Network uses graph items")
assert(lower_mask.kind == "graph" and inbound_fill.kind == "graph", "Network fill layers use graph items")
assert(baseline.kind == "graph", "Network baseline uses an overlay graph")
assert(outbound.component_size == 52 and lower_mask.component_size == 52, "upper Network chart layers are 52 pixels wide")
assert(inbound_fill.component_size == 52 and baseline.component_size == 52 and inbound.component_size == 52, "lower Network chart layers are 52 pixels wide")
assert(outbound.options.width == 0, "outbound graph overlays inbound graph")
assert(outbound.options.padding_right == lower_mask.options.padding_right, "outbound fill aligns with lower-half mask")
assert(inbound.options.updates == true and outbound.options.updates == true, "Network graphs update while hidden")
assert(outbound.options.graph.color == configured_colors.red, "outbound graph is red")
assert(inbound.options.graph.color == configured_colors.blue, "inbound graph is blue")
assert(outbound.options.graph.fill_color == configured_colors.with_alpha(configured_colors.red, 0.18), "outbound area uses translucent red fill")
assert(lower_mask.options.graph.color == configured_colors.transparent, "lower-half mask has no visible line")
assert(inbound_fill.options.graph.color == configured_colors.transparent, "inbound fill graph has no visible line")
assert(inbound_fill.options.graph.fill_color == configured_colors.with_alpha(configured_colors.blue, 0.18), "inbound area uses translucent blue fill")
assert(inbound.options.background.height == 22 and inbound.options.background.y_offset == 0, "inbound graph spans the centered packet canvas")
assert(outbound.options.background.height == 22 and outbound.options.background.y_offset == 0, "outbound graph spans the centered packet canvas")
assert(inbound.options.background.drawing == true and outbound.options.background.drawing == true, "packet graph canvases are visible")
assert(outbound.options.y_offset == -3 and lower_mask.options.y_offset == -3, "upper packet layers shift downward")
assert(inbound_fill.options.y_offset == -3 and baseline.options.y_offset == -3 and inbound.options.y_offset == -3, "lower packet layers shift downward")
assert(baseline.options.width == 0, "Network baseline does not consume layout width")
assert(baseline.options.padding_right == inbound.options.padding_right, "Network baseline aligns with inbound graph padding")
assert(baseline.options.background.height == 22 and baseline.options.background.y_offset == 0, "Network baseline spans the full chart")
assert(baseline.options.graph.color == configured_colors.grey, "Network baseline uses neutral grey")
assert(baseline.options.graph.fill_color == configured_colors.transparent, "Network baseline has no fill")
assert(baseline.options.graph.line_width == 1, "Network baseline is one pixel thick")
assert(#lower_mask.item.pushes == 52 and #inbound_fill.item.pushes == 52, "Network fill layers are prefilled across the graph width")
assert(#baseline.item.pushes == 52, "Network baseline is prefilled across the graph width")
for index = 1, 52 do
  assert(lower_mask.item.pushes[index][1] == 0.5, "lower-half mask starts at center")
  assert(inbound_fill.item.pushes[index][1] == 0.5, "inbound fill starts at center")
  assert(baseline.item.pushes[index][1] == 0.5, "Network baseline stays vertically centered")
end
assert(outbound.options.icon.string == configured_icons.wifi.bidirectional, "Network graph uses the combined up-down glyph")
assert(outbound.options.icon.padding_right == 4, "Network icon has extra spacing before the chart")
assert(outbound.options.icon.y_offset == 3, "Network icon remains vertically centered")
assert(inbound.options.icon.drawing == false, "inbound graph does not add a second icon")
assert(baseline.options.icon.drawing == false, "baseline does not add an icon")
assert(outbound.options.label.drawing == false, "icon-bearing graph has no overlapping label")
assert(baseline.options.label.string == "pkt ??:??", "Network label starts with packet ratio placeholder")
assert(baseline.options.label.width == 0 and baseline.options.label.align == "right", "Network label overlays the chart like other widgets")
local cpu_options = added["test.cpu.embedded"].options
assert(baseline.options.y_offset + baseline.options.label.y_offset
         == (cpu_options.y_offset or 0) + cpu_options.label.y_offset,
       "Network label lines up with the CPU label after the chart shift")
assert(baseline.options.label.font.family == configured_settings.font.numbers, "Network label uses numeric widget font")
assert(baseline.options.label.font.size == 9.0, "Network label matches other widget labels")
assert(inbound.options.label.drawing == false, "inbound graph has no duplicate label")
assert(#inbound.item.pushes == 52 and #outbound.item.pushes == 52, "packet graphs are prefilled across their width")
for index = 1, 52 do
  assert(inbound.item.pushes[index][1] == 0.5, "inbound history starts on center baseline")
  assert(outbound.item.pushes[index][1] == 0.5, "outbound history starts on center baseline")
end

local network_update = outbound.item.subscriptions["network_update"]
network_update({ packets_in = "80", packets_out = "20" })
assert(outbound.item.pushes[53][1] == 0.625, "outbound packets grow upward from center")
assert(inbound.item.pushes[53][1] == 0, "inbound packets grow downward from center")
assert(baseline.item.sets[1].label == "pkt 80:20", "Network label shows packet percentage split")
network_update({ packets_in = "0", packets_out = "0" })
assert(outbound.item.pushes[54][1] == 0.5, "outbound zero rate rests on center baseline")
assert(inbound.item.pushes[54][1] == 0.5, "inbound zero rate rests on center baseline")
assert(baseline.item.sets[2].label == "pkt 80:20", "Network ratio uses a rolling sample window")
network_update({ packets_in = "20", packets_out = "80" })
assert(baseline.item.sets[3].label == "pkt 50:50", "Network ratio averages recent packet samples")

network_module.new({ name = "test.network.single" })
assert(added["test.network.single.bracket"], "single Network adds bracket")
assert(added["test.network.single.padding"], "single Network adds padding")
local single_background = added["test.network.single.bracket"].options.background.color
assert(added["test.network.single.lower_mask"].options.graph.fill_color == single_background,
       "lower-half mask removes outbound fill below center")
assert(added["test.network.single.packets_in"].options.graph.fill_color == single_background,
       "inbound graph cuts fill below its line")

local function network_provider_starts()
  local count = 0
  for _, command in ipairs(executed) do
    if command:find("bin/network_load", 1, true) then count = count + 1 end
  end
  return count
end
assert(network_provider_starts() == 1, "Network provider starts once across constructors")

require("items.widgets.wifi")
assert(network_provider_starts() == 1, "Wi-Fi shares the Network provider")

print("network widget tests passed")

local persisted_metric = "disk\n"
_G.sbar.exec = function(command, callback)
  table.insert(executed, command)
  if callback then callback(persisted_metric) end
end

local system_monitor = require("items.widgets.system_monitor")
assert(type(system_monitor) == "table", "system monitor module loads")
assert(added["widgets.system_monitor.bracket"], "system monitor adds shared bracket")
assert(added["widgets.system_monitor.popup.cpu"], "system monitor adds CPU popup row")
assert(added["widgets.system_monitor.popup.memory"], "system monitor adds Memory popup row")
assert(added["widgets.system_monitor.popup.energy"], "system monitor adds Energy popup row")
assert(added["widgets.system_monitor.popup.disk"], "system monitor adds Disk popup row")
assert(added["widgets.system_monitor.popup.network"], "system monitor adds Network popup row")
local configured_icons = require("icons")
assert(
  added["widgets.system_monitor.popup.network"].options.icon.string == configured_icons.wifi.up_down,
  "Network popup uses the stacked up/down arrow symbol"
)
assert(added["widgets.system_monitor.popup.activity_monitor"], "system monitor adds Activity Monitor row")

local defaults_read_command
for _, command in ipairs(executed) do
  if command:find("defaults read com%.federico%.sketchybar system_monitor_metric") then
    defaults_read_command = command
  end
end
assert(defaults_read_command and defaults_read_command:find("2>/dev/null", 1, true), "missing preference is silent")

added["widgets.system_monitor.popup.memory"].item.subscriptions["mouse.clicked"]()
assert(executed[#executed]:find("system_monitor_metric %-string memory"), "memory selection persists")

added["widgets.system_monitor.popup.activity_monitor"].item.subscriptions["mouse.clicked"]()
assert(executed[#executed]:find("SelectedTab %-int 1"), "Activity Monitor opens selected Memory tab")

print("system monitor switcher tests passed")
