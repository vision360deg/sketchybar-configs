local M = {}

local valid_metrics = {
  cpu = true,
  memory = true,
  energy = true,
  disk = true,
  network = true,
}

local cpu_started = false
local network_started = false

function M.valid_metric(key)
  return valid_metrics[key] == true
end

function M.widget_mode(value)
  return value == "embedded" and "embedded" or "single"
end

function M.parse_memory_pressure(output)
  local free = tonumber(output:match("System%-wide memory free percentage:%s*(%d+)%%"))
  if not free then return nil end
  local used = math.max(0, math.min(100, 100 - free))
  return used / 100, used
end

function M.parse_disk_usage(output)
  local percent
  for line in output:gmatch("[^\r\n]+") do
    local value = line:match("(%d+)%%")
    if value then percent = tonumber(value) end
  end
  if not percent then return nil end
  percent = math.max(0, math.min(100, percent))
  return percent / 100, percent
end

function M.parse_energy_scores(output)
  local total = 0
  local found = false
  for line in output:gmatch("[^\r\n]+") do
    local value = tonumber(line:match("^%s*([%d%.]+)%s*$"))
    if value then
      total = total + value
      found = true
    end
  end
  return found and total or nil
end

function M.normalize_energy(value, peak)
  local next_peak = math.max(value, (peak or 0) * 0.95, 1)
  return math.min(value / next_peak, 1), next_peak
end

function M.normalize_packet_rates(packets_in, packets_out, peak)
  packets_in = math.max(tonumber(packets_in) or 0, 0)
  packets_out = math.max(tonumber(packets_out) or 0, 0)
  local next_peak = math.max(packets_in, packets_out, (peak or 0) * 0.95, 1)
  return math.min(packets_in / next_peak, 1), math.min(packets_out / next_peak, 1), next_peak
end

function M.packet_ratio(packets_in, packets_out)
  packets_in = math.max(tonumber(packets_in) or 0, 0)
  packets_out = math.max(tonumber(packets_out) or 0, 0)
  local total = packets_in + packets_out
  if total == 0 then return 50, 50 end

  local inbound_share = math.floor(packets_in / total * 100 + 0.5)
  return inbound_share, 100 - inbound_share
end

function M.start_cpu_provider()
  if cpu_started then return end
  cpu_started = true
  sbar.exec("killall cpu_load >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/cpu_load/bin/cpu_load cpu_update 2.0")
end

function M.start_network_provider()
  if network_started then return end
  network_started = true
  sbar.exec("killall network_load >/dev/null 2>&1; $CONFIG_DIR/helpers/event_providers/network_load/bin/network_load network_update 2.0")
end

return M
