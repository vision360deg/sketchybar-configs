package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded.colors = {
  transparent = 0,
  grey = 1,
  bg1 = 2,
  with_alpha = function(color) return color end,
}
package.loaded.icons = { switch = { on = "on", off = "off" } }
package.loaded.settings = {
  spaces_overlay_width = nil,
  spaces_fallback_width = 420,
  font = { style_map = { Heavy = "Heavy", Semibold = "Semibold", Black = "Black" } },
}
package.loaded["helpers.app_icons"] = { Default = "?" }

local triggered = {}

local function new_item(name, options)
  local item = { name = name, options = options or {}, subscriptions = {} }

  function item:subscribe(events, callback)
    if type(events) == "table" then
      for _, event in ipairs(events) do self.subscriptions[event] = callback end
    else
      self.subscriptions[events] = callback
    end
  end

  function item:set(value)
    for key, property in pairs(value) do self.options[key] = property end
  end

  function item:query()
    return {
      bounding_rects = {
        ["1"] = { origin = { 10, 2 }, size = { 420, 26 } },
        ["2"] = { origin = { -1250, 2 }, size = { 140, 26 } },
      },
    }
  end

  return item
end

local state_output = table.concat({
  "D\t1\t0\t0\t1512\t982\tfalse",
  "D\t2\t-1512\t0\t1512\t982\ttrue",
  "S\t1\t1\ttrue\tfalse",
  "S\t2\t1\tfalse\tfalse",
  "S\t3\t2\ttrue\ttrue",
  "S\t4\t2\tfalse\tfalse",
  "W\t1\t101\tSafari\tfalse\tfalse\ttrue\ttrue\t1",
  "W\t3\t303\tTerminal\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t3\t304\tMail\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t3\t305\tMusic\tfalse\tfalse\tfalse\ttrue\t2",
  "END",
}, "\n") .. "\n"

local added = {}

_G.sbar = {
  add = function(_, name, options)
    if type(name) == "table" then
      options = name
      name = "anonymous"
    end
    local item = new_item(name, options)
    added[name] = item
    return item
  end,
  exec = function(command, callback)
    if not callback then return end
    if command:find("query --windows", 1, true) then
      callback(state_output)
    else
      callback("")
    end
  end,
  trigger = function(_, env)
    triggered[#triggered + 1] = env
  end,
  delay = function() end,
  animate = function(_, _, callback) callback() end,
}

local spaces = require("items.spaces")
spaces.start(new_item("front_app"), { hide = function() end, show = function() end })

local payload = triggered[#triggered]
assert(payload and payload.DISPLAYS, "sync payload carries DISPLAYS groups")

local groups = {}
for group in payload.DISPLAYS:gmatch("[^;]+") do groups[#groups + 1] = group end
assert(#groups == 2, "one group per display")

local function fields(group)
  local result = {}
  for field in group:gmatch("[^|]+") do result[#result + 1] = field end
  return result
end

local first = fields(groups[1])
local second = fields(groups[2])

assert(tonumber(first[1]) == 1, "first group is display one")
assert(first[7] == "1,2", "display one shows only its own spaces")
assert(tonumber(first[6]) == 0, "display without focused space has no selection")
assert(math.abs(tonumber(first[2]) - 10) < 0.001, "bar display keeps its overlay origin")
assert(math.abs(tonumber(first[4]) - 126.04) < 0.001, "bar display hugs its own spaces")

assert(tonumber(second[1]) == 2, "second group is display two")
assert(second[7] == "3,4", "display two shows only its own spaces")
assert(tonumber(second[6]) == 3, "focused space selects on its own display")
assert(math.abs(tonumber(second[2]) - (-1250)) < 0.001, "secondary display uses its own measured bar rect")
assert(math.abs(tonumber(second[3]) - 2) < 0.001, "secondary display mirrors the bar edge offset")
assert(math.abs(tonumber(second[4]) - 140) < 0.001, "panel caps at the bar item width so overflowing cards scroll")
assert(math.abs(tonumber(second[5]) - 26) < 0.001, "secondary display reuses overlay height")

assert(first[8] == "536166617269,", "first display encodes its own space labels")
assert(first[9] == "101,", "first display encodes its own window IDs")
assert(first[10] == "101,", "first display encodes its own foreground IDs")
assert(second[8] == "4d61696c1f4d757369631f5465726d696e616c,", "second display encodes its own space labels")
assert(second[9] == "304:305:303,", "second display encodes its own window IDs")
assert(second[10] == ",", "second display has no foreground window")

local function latest_groups()
  local latest = {}
  for group in triggered[#triggered].DISPLAYS:gmatch("[^;]+") do
    latest[#latest + 1] = fields(group)
  end
  return latest
end

-- Focus moves to display one by clicking a window there: no space changes, so
-- only a fresh yabai snapshot can move the highlight.
state_output = state_output
  :gsub("D\t1\t0\t0\t1512\t982\tfalse", "D\t1\t0\t0\t1512\t982\ttrue")
  :gsub("D\t2\t%-1512\t0\t1512\t982\ttrue", "D\t2\t-1512\t0\t1512\t982\tfalse")
  :gsub("S\t1\t1\ttrue\tfalse", "S\t1\t1\ttrue\ttrue")
  :gsub("S\t3\t2\ttrue\ttrue", "S\t3\t2\ttrue\tfalse")
added["spaces.state_observer"].subscriptions["display_change"]({})
local refocused = latest_groups()
assert(tonumber(refocused[1][6]) == 1, "focus on display one selects its visible space")
assert(tonumber(refocused[2][6]) == 0, "display two drops its selection when it loses focus")

-- Unplugging display two moves its spaces to display one without creating or
-- destroying a space; the grouping must follow yabai's space-to-display map.
state_output = state_output
  :gsub("D\t2\t[^\n]*\n", "")
  :gsub("S\t3\t2\t", "S\t3\t1\t")
  :gsub("S\t4\t2\t", "S\t4\t1\t")
added["spaces.state_observer"].subscriptions["display_change"]({})
local merged = latest_groups()
assert(#merged == 1 and merged[1][7] == "1,2,3,4",
       "spaces of a removed display move to the remaining display")

print("spaces overlay display group tests passed")
