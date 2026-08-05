local M = {}

local tabs = {
  cpu = { index = 0, name = "CPU" },
  memory = { index = 1, name = "Memory" },
  energy = { index = 2, name = "Energy" },
  disk = { index = 3, name = "Disk" },
  network = { index = 4, name = "Network" },
}

local function tab(key)
  return tabs[key] or tabs.cpu
end

function M.tab_index(key)
  return tab(key).index
end

function M.tab_name(key)
  return tab(key).name
end

function M.open(key)
  local selected = tab(key)
  local ordinal = selected.index + 1
  local command = string.format([[
    defaults write com.apple.ActivityMonitor SelectedTab -int %d
    open -a 'Activity Monitor'
    osascript \
      -e 'tell application "Activity Monitor" to activate' \
      -e 'tell application "System Events"' \
      -e 'tell process "Activity Monitor"' \
      -e 'repeat 40 times' \
      -e 'if exists window 1 then exit repeat' \
      -e 'delay 0.1' \
      -e 'end repeat' \
      -e 'try' \
      -e 'click radio button %d of radio group 1 of group 1 of toolbar 1 of window 1' \
      -e 'end try' \
      -e 'end tell' \
      -e 'end tell'
  ]], selected.index, ordinal)
  sbar.exec(command)
end

return M
