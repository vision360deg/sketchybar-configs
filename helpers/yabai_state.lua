local M = {}

local yabai = "/opt/homebrew/bin/yabai"
local jq = "/opt/homebrew/bin/jq"

-- One consistent snapshot of displays, spaces and windows. yabai names windows
-- it holds no Accessibility reference for after their process (for example
-- "wezterm-gui"); reuse the application name of a referenced sibling window.
-- A failed or truncated reply leaves jq without three valid documents, so the
-- END sentinel is missing and parse() rejects the output.
local program = [[
if length == 3 then
  .[0] as $displays | .[1] as $spaces | .[2] as $windows
  | (reduce ($windows[] | select(."has-ax-reference" != false)) as $window
      ({}; .[$window.pid | tostring] = $window.app)) as $app_by_pid
  | ($displays[] | ["D", .index, .frame.x, .frame.y, .frame.w, .frame.h, ."has-focus"] | @tsv),
    ($spaces[] | ["S", .index, .display, ."is-visible", ."has-focus"] | @tsv),
    ($windows[] | ["W", .space, .id, ($app_by_pid[.pid | tostring] // .app // ""),
      ."is-minimized", ."is-hidden", ."has-focus", ."has-ax-reference", .display] | @tsv),
    "END"
else empty end
]]

M.query = "export USER=$(/usr/bin/id -un); { "
  .. yabai .. " -m query --displays && "
  .. yabai .. " -m query --spaces && "
  .. yabai .. " -m query --windows; } 2>/dev/null | "
  .. jq .. " -rs '" .. program .. "' 2>/dev/null"

local function fields(line)
  local result = {}
  for field in (line .. "\t"):gmatch("([^\t]*)\t") do result[#result + 1] = field end
  return result
end

-- Returns { displays = { [index] = frame }, spaces = { ... }, windows = { ... } },
-- or nil for incomplete output so callers keep their last good state.
function M.parse(output)
  if type(output) ~= "string" then return nil end

  local state = { displays = {}, spaces = {}, windows = {} }
  local complete = false
  for line in output:gmatch("[^\r\n]+") do
    local field = fields(line)
    local kind = field[1]
    if kind == "D" then
      local index = tonumber(field[2])
      local x, y = tonumber(field[3]), tonumber(field[4])
      local width, height = tonumber(field[5]), tonumber(field[6])
      if index and x and y and width and height and width > 0 and height > 0 then
        state.displays[index] = {
          x = x,
          y = y,
          width = width,
          height = height,
          focused = field[7] == "true",
        }
      end
    elseif kind == "S" then
      local index = tonumber(field[2])
      if index and index >= 1 then
        state.spaces[#state.spaces + 1] = {
          index = index,
          display = tonumber(field[3]),
          visible = field[4] == "true",
          focused = field[5] == "true",
        }
      end
    elseif kind == "W" then
      local space, id = tonumber(field[2]), tonumber(field[3])
      if space and id then
        state.windows[#state.windows + 1] = {
          space = space,
          id = id,
          app = field[4] or "",
          minimized = field[5] == "true",
          hidden = field[6] == "true",
          focused = field[7] == "true",
          ax_reference = field[8] ~= "false",
          display = tonumber(field[9]),
        }
      end
    elseif kind == "END" then
      complete = true
    end
  end

  if not complete or #state.spaces == 0 or next(state.displays) == nil then return nil end
  return state
end

return M
