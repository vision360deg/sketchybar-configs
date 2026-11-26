package.path = "./?.lua;./?/init.lua;" .. package.path

local windows = require("helpers.space_windows")

local function window(space, id, app, fields)
  local record = {
    space = space,
    id = id,
    app = app,
    minimized = false,
    hidden = false,
    focused = false,
    ax_reference = true,
    display = 1,
  }
  for key, value in pairs(fields or {}) do record[key] = value end
  return record
end

local records = windows.rebuild({
  window(1, 101, "Safari", { focused = true }),
  window(1, 102, "Safari", { minimized = true }),
  window(1, 103, "Safari", { hidden = true }),
  window(2, 201, "Terminal", { focused = true }),
  window(2, 202, ""),
  window(3, 301, "Code"),
  window(0, 999, "Ignored", { focused = true }),
}, 3)

assert(#records[1] == 1 and records[1][1].id == 101,
       "drops minimized and hidden windows")
assert(records[1][1].app == "Safari", "keeps the owning app")
assert(#records[2] == 2 and records[2][2].id == 202,
       "keeps a window with a missing app name")
assert(#records[3] == 1 and records[3][1].id == 301,
       "keeps normal windows without a focused flag")

-- UTM keeps an untitled helper window that yabai lists on some space but can
-- never reference; it used to show up as an empty preview there.
local unreferenced = windows.rebuild({
  window(1, 104, "UTM", { ax_reference = false }),
  window(2, 204, "WezTerm", { ax_reference = false }),
}, 3)
assert(#unreferenced[1] == 0 and #unreferenced[2] == 0,
       "drops windows yabai holds no Accessibility reference for, on every space")

local suppressed = windows.rebuild({ window(2, 205, "Safari") }, 3, nil, {
  suppressed_ids = { [205] = true },
})
assert(#suppressed[2] == 0, "drops a window yabai reported as destroyed")

local focusable = windows.rebuild({
  window(2, 206, "Safari"),
  window(2, 207, "Mail"),
}, 3)
assert(windows.focus_target(focusable[2], 206) == 206,
       "focuses the space's foreground window")
assert(windows.focus_target(focusable[2], 999) == 207,
       "falls back to the space's first window when the foreground one left")
assert(windows.focus_target({}, nil) == nil, "has no target on an empty space")

local apps = windows.apps(records, 3)
assert(#apps[1] == 1 and apps[1][1] == "Safari", "deduplicates app labels")
assert(#apps[2] == 1 and apps[2][1] == "Terminal",
       "does not create a label for an empty app name")
assert(windows.serialize_ids(records, 3) == "101,201:202,301",
       "serializes per-space ID groups")

local ordered_records = windows.rebuild({
  window(1, 104, "WezTerm"),
  window(1, 102, "Safari"),
  window(1, 101, "WezTerm"),
}, 3)
assert(windows.serialize_ids(ordered_records, 3) == "102:101:104,,",
       "orders windows by the same app order used by the space card")

local focus_refreshed_records = windows.rebuild({
  window(1, 104, "WezTerm", { focused = true }),
  window(1, 101, "WezTerm"),
  window(1, 102, "Safari"),
}, 3, ordered_records)
assert(windows.serialize_ids(focus_refreshed_records, 3) == "102:101:104,,",
       "does not reorder preview windows when focus changes")

local new_window_records = windows.rebuild({
  window(1, 99, "WezTerm"),
  window(1, 104, "WezTerm"),
  window(1, 101, "WezTerm"),
}, 3, ordered_records)
assert(windows.serialize_ids(new_window_records, 3) == "101:104:99,,",
       "appends new windows after the known order of their app")

-- Closing a window between refreshes reorders yabai's output; the comparator
-- used to report a known window as smaller than itself, which made table.sort
-- raise "invalid order function for sorting" and dropped the refresh.
math.randomseed(7)
local names = { "Safari", "WezTerm", "Finder", "" }
for _ = 1, 2000 do
  local list = {}
  for index = 1, math.random(4, 12) do
    list[index] = window(1, 100 + index, names[math.random(#names)])
  end
  local previous = windows.rebuild(list, 1)
  table.remove(list, math.random(#list))
  for index = #list, 2, -1 do
    local other = math.random(index)
    list[index], list[other] = list[other], list[index]
  end
  local ok, result = pcall(windows.rebuild, list, 1, previous)
  assert(ok, "rebuild survives a closed window: " .. tostring(result))
  assert(#result[1] == #list, "rebuild keeps every remaining window")
end

local foreground = windows.foreground_ids(records, 3, {
  [1] = 999,
  [2] = 202,
  [3] = 301,
})
assert(foreground[1] == 101, "records the focused window in space one")
assert(foreground[2] == 201, "records the focused window in space two")
assert(foreground[3] == 301, "preserves the last known foreground window")
assert(windows.serialize_foreground_ids(foreground, 3) == "101,201,301",
       "serializes one foreground window per space")

print("space window tests passed")
