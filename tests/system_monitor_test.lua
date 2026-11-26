package.path = "./?.lua;./?/init.lua;" .. package.path

local metrics = require("helpers.system_metrics")

local function equal(actual, expected, message)
  assert(actual == expected, string.format("%s: expected %s, got %s", message, tostring(expected), tostring(actual)))
end

local function near(actual, expected, message)
  assert(math.abs(actual - expected) < 0.0001, string.format("%s: expected %.4f, got %.4f", message, expected, actual))
end

equal(metrics.valid_metric("cpu"), true, "cpu is valid")
equal(metrics.valid_metric("network"), true, "network is valid")
equal(metrics.valid_metric("gpu"), false, "gpu is invalid")
equal(metrics.widget_mode("embedded"), "embedded", "embedded mode")
equal(metrics.widget_mode("invalid"), "single", "invalid mode")
equal(metrics.widget_mode(nil), "single", "missing mode")

local memory_fraction, memory_percent = metrics.parse_memory_pressure(
  "System-wide memory free percentage: 37%\n"
)
near(memory_fraction, 0.63, "memory fraction")
equal(memory_percent, 63, "memory percent")
equal(metrics.parse_memory_pressure("unexpected output"), nil, "invalid memory output")

local disk_fraction, disk_percent = metrics.parse_disk_usage(
  "Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/disk3s1 100 54 46 54% /\n"
)
near(disk_fraction, 0.54, "disk fraction")
equal(disk_percent, 54, "disk percent")
equal(metrics.parse_disk_usage("no percentage"), nil, "invalid disk output")

equal(metrics.parse_energy_scores("POWER\n0.0\n12.5\n7.5\n"), 20, "energy total")
equal(metrics.parse_energy_scores("POWER\n"), nil, "empty energy output")

local normalized, peak = metrics.normalize_energy(20, 10)
near(normalized, 1, "new energy peak")
equal(peak, 20, "peak increases")

normalized, peak = metrics.normalize_energy(10, 20)
near(normalized, 10 / 19, "energy uses decayed peak")
near(peak, 19, "peak decays five percent")

normalized, peak = metrics.normalize_energy(0, 0)
near(normalized, 0, "zero energy normalizes")
equal(peak, 1, "zero energy minimum peak")

local packets_in, packets_out, packet_peak = metrics.normalize_packet_rates(80, 20, 40)
near(packets_in, 1, "inbound packets set shared peak")
near(packets_out, 0.25, "outbound packets share inbound peak")
equal(packet_peak, 80, "packet peak grows")

packets_in, packets_out, packet_peak = metrics.normalize_packet_rates(19, 38, 40)
near(packets_in, 0.5, "inbound packets use decayed peak")
near(packets_out, 1, "outbound packets reach decayed peak")
near(packet_peak, 38, "packet peak decays five percent")

packets_in, packets_out, packet_peak = metrics.normalize_packet_rates(0, 0, 0)
near(packets_in, 0, "zero inbound packets")
near(packets_out, 0, "zero outbound packets")
equal(packet_peak, 1, "packet peak minimum")

local inbound_share, outbound_share = metrics.packet_ratio(75, 25)
equal(inbound_share, 75, "packet ratio inbound share")
equal(outbound_share, 25, "packet ratio outbound share")

inbound_share, outbound_share = metrics.packet_ratio(1, 2)
equal(inbound_share, 33, "packet ratio rounds inbound share")
equal(outbound_share, 67, "packet ratio preserves total")

inbound_share, outbound_share = metrics.packet_ratio(0, 0)
equal(inbound_share, 50, "idle packet ratio is balanced")
equal(outbound_share, 50, "idle packet ratio totals one hundred")

local activity_monitor = require("helpers.activity_monitor")

equal(activity_monitor.tab_index("cpu"), 0, "CPU tab")
equal(activity_monitor.tab_index("memory"), 1, "Memory tab")
equal(activity_monitor.tab_index("energy"), 2, "Energy tab")
equal(activity_monitor.tab_index("disk"), 3, "Disk tab")
equal(activity_monitor.tab_index("network"), 4, "Network tab")
equal(activity_monitor.tab_index("invalid"), 0, "invalid tab falls back")
equal(activity_monitor.tab_name("energy"), "Energy", "Energy name")

local activity_command
_G.sbar = { exec = function(command) activity_command = command end }
activity_monitor.open("energy")
assert(activity_command:find("SelectedTab %-int 2"), "Energy launch stores tab index")
assert(activity_command:find("radio button 3"), "Energy launch selects third toolbar tab")
assert(activity_command:find("radio group 1 of group 1 of toolbar 1"), "Activity Monitor selector includes toolbar group")
assert(activity_command:find("repeat 40 times"), "Activity Monitor waits for its window")

local configured_icons = require("icons")
equal(
  configured_icons.system_monitor.activity_monitor,
  "􀟪",
  "Activity Monitor uses outline ECG rectangle icon"
)
equal(
  configured_icons.wifi.network_settings,
  "􀆪",
  "Network Settings uses warped globe icon"
)

local system_settings = require("helpers.system_settings")
local settings_command
_G.sbar.exec = function(command) settings_command = command end
system_settings.open("network")
equal(
  settings_command,
  "open 'x-apple.systempreferences:com.apple.Network-Settings.extension'",
  "Network settings opens the Network pane directly"
)

settings_command = nil
local opened_settings, settings_error = pcall(system_settings.open, "invalid")
equal(opened_settings, true, "invalid settings key falls back: " .. tostring(settings_error))
equal(
  settings_command,
  "open 'x-apple.systempreferences:com.apple.Network-Settings.extension'",
  "invalid settings key falls back to Network"
)

print("system monitor helper tests passed")
