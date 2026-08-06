local M = {}

local panes = {
  network = {
    name = "Network",
    url = "x-apple.systempreferences:com.apple.Network-Settings.extension",
  },
}

local function pane(key)
  return panes[key] or panes.network
end

function M.tab_name(key)
  return pane(key).name
end

function M.open(key)
  local selected = pane(key)
  sbar.exec(string.format("open '%s'", selected.url))
end

return M
