package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded.colors = {
  transparent = 0,
  grey = 0,
  bg1 = 0,
  with_alpha = function(color) return color end,
}
package.loaded.icons = { switch = { on = "on", off = "off" }, reload = "reload" }
package.loaded.settings = {
  paddings = 1,
  spaces_overlay_width = nil,
  spaces_fallback_width = 420,
  font = { style_map = { Heavy = "Heavy", Semibold = "Semibold", Black = "Black" } },
}
package.loaded["helpers.app_icons"] = { Default = "?" }

local added = {}
local operations = {}
local delayed_callbacks = {}
local executed_commands = {}

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
  if value.width then self.options.width = value.width end
  if value.drawing ~= nil then self.options.drawing = value.drawing end
  if value.label and value.label.width ~= nil then
    self.options.label.width = value.label.width
  end
  table.insert(operations, { kind = "item_set", name = self.name, value = value })
end


function item:query()
  local origin_x = 10
  local width = self.options.width or 1
  if self.name == "spaces.overlay" and self.options.drawing == false then
    origin_x = -9999
  elseif self.name:match("^spaces%.indicator%.%d+$") then
    local display_index = tonumber(self.name:match("(%d+)$")) or 1
    origin_x = 420 + display_index * 40
    width = self.options.label.width == "dynamic" and 83 or 29
  elseif self.name == "front_app" then
    origin_x, width = 459, 70
  elseif self.name == "spaces.right_boundary" then
    origin_x, width = 900, 1
  end

  return {
    icon = { value = "on" },
    geometry = { drawing = "off" },
    bounding_rects = {
      ["1"] = { origin = { origin_x, 2 }, size = { width, 26 } },
    },
  }
end


  return item
end

local yabai_state_output = table.concat({
  "D\t1\t0\t0\t1512\t982\ttrue",
  "D\t2\t-1512\t0\t1512\t982\tfalse",
  "S\t1\t1\ttrue\ttrue",
  "S\t2\t1\tfalse\tfalse",
  "S\t3\t2\ttrue\tfalse",
  "S\t4\t2\tfalse\tfalse",
  "S\t5\t1\tfalse\tfalse",
  "S\t6\t1\tfalse\tfalse",
  "S\t7\t2\tfalse\tfalse",
  "S\t8\t2\tfalse\tfalse",
  "W\t1\t101\tSafari\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t1\t102\tFinder\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t2\t201\tTerminal\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t2\t202\tNotes\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t3\t301\tMail\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t3\t302\tCalendar\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t4\t401\tCode\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t4\t402\tSlack\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t5\t501\tMusic\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t5\t502\tPodcasts\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t6\t601\tPreview\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t6\t602\tPhotos\tfalse\tfalse\tfalse\ttrue\t1",
  "W\t7\t701\tMessages\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t7\t702\tMaps\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t8\t801\tSystem\tfalse\tfalse\tfalse\ttrue\t2",
  "W\t8\t802\tSettings\tfalse\tfalse\tfalse\ttrue\t2",
  "END",
}, "\n") .. "\n"

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
  remove = function(name)
    table.insert(operations, { kind = "remove", name = name })
  end,
  query = function(name)
    if name == "bar" then return { geometry = { height = 28 } } end
    return nil
  end,
  set = function(name, value)
    table.insert(operations, { kind = "set", name = name, value = value })
  end,
  trigger = function(name, value)
    table.insert(operations, { kind = "trigger", name = name, value = value })
  end,
delay = function(_, callback)
  table.insert(operations, { kind = "delay" })
  table.insert(delayed_callbacks, callback)
end,

  exec = function(command, callback)
    table.insert(executed_commands, command)
    if not callback then return end
    if command:find("query --windows", 1, true) then
      callback(yabai_state_output)
    else
      callback("")
    end
  end,
  animate = function(_, _, callback) callback() end,
}

local menus = require("items.menus")
assert(type(menus.show) == "function", "menus exports a show controller method")
assert(type(menus.hide) == "function", "menus exports a hide controller method")

local spaces = require("items.spaces")
local front_app = new_item("front_app")
spaces.start(front_app, menus)
local window_query_has_user = false
for _, command in ipairs(executed_commands) do
  if command:find("query --windows", 1, true)
      and command:find("USER=$(/usr/bin/id -un)", 1, true) then
    window_query_has_user = true
  end
end
assert(window_query_has_user,
       "window query supplies USER for yabai under LaunchAgent")
local initial_window_snapshot
for _, operation in ipairs(operations) do
  if operation.kind == "trigger"
      and operation.name == "spaces_overlay_sync"
      and operation.value
      and operation.value.WINDOW_IDS
      and operation.value.WINDOW_IDS:find("102:101", 1, true) then
    initial_window_snapshot = operation.value
  end
end
assert(initial_window_snapshot,
       "startup sync loads window IDs before the first hover")
operations = {}
added["spaces.state_observer"].subscriptions["space_windows_change"]({ INFO = { space = "1" } })
assert(added["spaces.right_boundary"], "automatic width adds a right-side geometry boundary")
assert(added["spaces.indicator.1"] and added["spaces.indicator.2"],
       "creates one Spaces toggle per display")
assert(added["spaces.indicator.1"].options.display == 1
    and added["spaces.indicator.2"].options.display == 2,
       "scopes each Spaces toggle to its own display")
assert(added["spaces.indicator.1"].options.padding_left == 2,
       "Spaces toggle keeps five additional points of left padding")
for _, callback in ipairs(delayed_callbacks) do callback() end
local automatic_width
for _, operation in ipairs(operations) do
  if operation.kind == "item_set"
      and operation.name == "spaces.overlay"
      and operation.value.width then
    automatic_width = operation.value.width
  end
end
assert(automatic_width == 725, "collapsed calculation reserves the expanded toggle width")
assert(added["spaces.indicator.1"].options.label.width == 0,
       "Spaces label collapses after its expanded width is measured")

local window_snapshot
for _, operation in ipairs(operations) do
  if operation.kind == "trigger" and operation.name == "spaces_overlay_sync" then
    window_snapshot = operation.value
  end
end
assert(window_snapshot and window_snapshot.WINDOW_IDS,
       "window-change snapshot publishes WINDOW_IDS")

local delayed_start = #delayed_callbacks
operations = {}
added["spaces.swap_observer"].subscriptions["swap_menus_and_spaces"]()
added["spaces.geometry_observer"].subscriptions["front_app_switched"]()
local delayed_index = delayed_start + 1
while delayed_index <= #delayed_callbacks do
  delayed_callbacks[delayed_index]()
  delayed_index = delayed_index + 1
end
for _, operation in ipairs(operations) do
  assert(not (operation.kind == "item_set"
      and operation.name == "spaces.overlay"
      and operation.value.width == 420),
      "hidden geometry refresh preserves the last calculated width")
end
added["spaces.swap_observer"].subscriptions["swap_menus_and_spaces"]()

operations = {}
added["spaces.indicator.1"].subscriptions["mouse.entered"]()
assert(added["spaces.indicator.1"].options.label.width == "dynamic",
       "hovering one Spaces toggle expands that display's label")
assert(added["spaces.indicator.2"].options.label.width == 0,
       "hovering one Spaces toggle leaves other displays collapsed")
added["spaces.indicator.1"].subscriptions["mouse.exited"]()
assert(added["spaces.indicator.1"].options.label.width == 0,
       "leaving one Spaces toggle collapses only that display")
for _, operation in ipairs(operations) do
  assert(operation.kind ~= "delay", "toggle hover does not schedule geometry recalculation")
end

operations = {}
added["spaces.swap_observer"].subscriptions["swap_menus_and_spaces"]()

local visibility_trigger
local first_menu_operation
for index, operation in ipairs(operations) do
  if operation.kind == "trigger"
      and operation.name == "spaces_overlay_sync"
      and operation.value
      and operation.value.VISIBLE == "false" then
    visibility_trigger = index
  end
  if not first_menu_operation
      and ((operation.kind == "set" and operation.name == "/menu\\..*/")
        or (operation.kind == "item_set" and operation.name == "menu.padding")) then
    first_menu_operation = index
  end
end

assert(visibility_trigger, "toggle sends native visibility immediately")
local _, separator_count = operations[visibility_trigger].value.LABELS:gsub(",", "")
assert(separator_count == 7, "snapshot contains exactly eight active spaces")
assert(first_menu_operation and visibility_trigger < first_menu_operation,
       "native visibility is sent before SketchyBar menu visibility changes")

for _, operation in ipairs(operations) do
  assert(operation.kind ~= "delay", "toggle visibility does not use deferred geometry sync")
end


operations = {}
added["spaces.swap_observer"].subscriptions["swap_menus_and_spaces"]()

local show_trigger
local first_hide_operation
for index, operation in ipairs(operations) do
  if operation.kind == "trigger"
      and operation.name == "spaces_overlay_sync"
      and operation.value
      and operation.value.VISIBLE == "true" then
    show_trigger = index
  end
  if not first_hide_operation
      and ((operation.kind == "set" and operation.name == "/menu\\..*/")
        or (operation.kind == "item_set" and operation.name == "menu.padding")) then
    first_hide_operation = index
  end
end

assert(show_trigger, "reverse toggle sends native visibility immediately")
assert(first_hide_operation and show_trigger < first_hide_operation,
       "native overlay show is sent before SketchyBar menus are hidden")
for _, operation in ipairs(operations) do
  assert(operation.kind ~= "delay", "reverse toggle visibility does not use deferred geometry sync")
end

local press_observer = added["spaces.press_observer"]
assert(press_observer and press_observer.subscriptions["mouse_clicked_global"],
       "Spaces toggle observes global mouse-down events")

local function reload_command_count()
  local count = 0
  for _, command in ipairs(executed_commands) do
    if command:find("hard_reload.sh", 1, true) then count = count + 1 end
  end
  return count
end

local function swap_trigger_count()
  local count = 0
  for _, operation in ipairs(operations) do
    if operation.kind == "trigger" and operation.name == "swap_menus_and_spaces" then
      count = count + 1
    end
  end
  return count
end

local function reload_hint_shown(display_index)
  local shown
  for _, operation in ipairs(operations) do
    if operation.kind == "item_set"
        and operation.name == "spaces.indicator." .. display_index
        and operation.value.icon and operation.value.icon.string then
      shown = operation.value.icon.string == "reload"
    end
  end
  return shown
end

local indicator = added["spaces.indicator.1"]
local other_indicator = added["spaces.indicator.2"]
local reload_before = reload_command_count()
local left_click = { BUTTON = "left" }
local right_click = { BUTTON = "right" }

operations = {}
indicator.subscriptions["mouse.clicked"](left_click)
assert(swap_trigger_count() == 1 and reload_command_count() == reload_before,
       "a click toggles spaces and menus")

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
assert(reload_hint_shown(1), "a right click switches the toggle to Reload")
assert(swap_trigger_count() == 0 and reload_command_count() == reload_before,
       "a right click neither toggles nor reloads")

operations = {}
indicator.subscriptions["mouse.exited"]()
assert(reload_hint_shown(1) == true, "leaving the toggle keeps its Reload state")

operations = {}
other_indicator.subscriptions["mouse.clicked"](left_click)
assert(swap_trigger_count() == 1 and reload_command_count() == reload_before,
       "another display's toggle still toggles spaces and menus")

operations = {}
indicator.subscriptions["mouse.clicked"](left_click)
assert(reload_command_count() == reload_before + 1, "clicking Reload runs the hard reload")
assert(swap_trigger_count() == 0, "clicking Reload does not also toggle spaces and menus")
assert(reload_hint_shown(1) == false, "the toggle leaves its Reload state")

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
indicator.subscriptions["mouse.clicked"](right_click)
assert(reload_hint_shown(1) == false, "a second right click cancels Reload")
operations = {}
indicator.subscriptions["mouse.clicked"](left_click)
assert(reload_command_count() == reload_before + 1 and swap_trigger_count() == 1,
       "after cancelling, a click toggles spaces and menus again")

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
other_indicator.subscriptions["mouse.clicked"](right_click)
assert(reload_hint_shown(1) == false and reload_hint_shown(2) == true,
       "arming another display's toggle cancels the first one")
other_indicator.subscriptions["mouse.clicked"](right_click)
-- The global mouse-down cancels "Reload" unless it lands on that toggle, where it
-- is the click that runs the reload (or the late report of the arming right click).
local function press_at(x, y)
  press_observer.subscriptions["mouse_clicked_global"]({ BUTTON = "left", MOUSE_X = x, MOUSE_Y = y })
end

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
press_at("470", "10")
assert(reload_hint_shown(1) == true, "a mouse-down on the Reload toggle keeps it")
indicator.subscriptions["mouse.clicked"](left_click)
assert(reload_command_count() == reload_before + 2, "the click on Reload still reloads")

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
press_at("200", "10")
assert(reload_hint_shown(1) == false, "a click elsewhere on the bar cancels Reload")
indicator.subscriptions["mouse.clicked"](left_click)
assert(reload_command_count() == reload_before + 2 and swap_trigger_count() == 1,
       "after a click elsewhere, the toggle toggles spaces and menus again")

operations = {}
indicator.subscriptions["mouse.clicked"](right_click)
press_at("700", "500")
assert(reload_hint_shown(1) == false, "a click outside the bar cancels Reload too")

operations = {}
press_at("200", "10")
assert(reload_hint_shown(1) == nil, "a click while nothing shows Reload changes no toggle")

local function restack_count()
  local count = 0
  for _, operation in ipairs(operations) do
    if operation.kind == "remove" and operation.name == "spaces.restack" then count = count + 1 end
  end
  return count
end

-- A click on the bar's empty space raises its background window over the items.
operations = {}
local restack_delay_index = #delayed_callbacks
press_at("700", "10")
assert(restack_count() == 1, "a click on the bar restacks SketchyBar's windows right away")
for index = restack_delay_index + 1, #delayed_callbacks do delayed_callbacks[index]() end
assert(restack_count() == 2, "and again shortly after, in case the raise came late")
operations = {}
press_at("700", "300")
assert(restack_count() == 0, "a click below the bar leaves SketchyBar's windows alone")

local function focus_command_count(display_index)
  local marker = "display --focus " .. display_index
  local count = 0
  for _, command in ipairs(executed_commands) do
    if command:find(marker, 1, true) then count = count + 1 end
  end
  return count
end

local focus_before = focus_command_count(2)
press_observer.subscriptions["mouse_clicked_global"]({
  BUTTON = "right",
  MOUSE_X = "-900",
  MOUSE_Y = "10",
})
assert(focus_command_count(2) == focus_before + 1,
       "clicking an inactive display's bar focuses that display")

local active_focus_before = focus_command_count(1)
press_observer.subscriptions["mouse_clicked_global"]({
  BUTTON = "right",
  MOUSE_X = "470",
  MOUSE_Y = "10",
})
assert(focus_command_count(1) == active_focus_before,
       "clicking the active display's bar does not refocus it")

local below_bar_focus_before = focus_command_count(2)
press_observer.subscriptions["mouse_clicked_global"]({
  BUTTON = "right",
  MOUSE_X = "-900",
  MOUSE_Y = "100",
})
assert(focus_command_count(2) == below_bar_focus_before,
       "clicking below the bar does not focus a display")

-- Move focus to display two, then click display one's bar. The overlay panel
-- (x 10 to the width of its cards) focuses a clicked space on its own; a
-- display focus at the same time could undo that switch.
yabai_state_output = yabai_state_output
  :gsub("D\t1\t0\t0\t1512\t982\ttrue", "D\t1\t0\t0\t1512\t982\tfalse")
  :gsub("D\t2\t%-1512\t0\t1512\t982\tfalse", "D\t2\t-1512\t0\t1512\t982\ttrue")
added["spaces.state_observer"].subscriptions["display_change"]({})

local panel_focus_before = focus_command_count(1)
press_observer.subscriptions["mouse_clicked_global"]({
  BUTTON = "right",
  MOUSE_X = "40",
  MOUSE_Y = "10",
})
assert(focus_command_count(1) == panel_focus_before,
       "clicking an inactive display's spaces overlay leaves focusing to the overlay")

press_observer.subscriptions["mouse_clicked_global"]({
  BUTTON = "right",
  MOUSE_X = "600",
  MOUSE_Y = "10",
})
assert(focus_command_count(1) == panel_focus_before + 1,
       "clicking elsewhere on an inactive display's bar still focuses it")

local function space_focus_command(space)
  local before = #executed_commands
  added["spaces.state_observer"].subscriptions["spaces_focus"]({ SPACE = tostring(space) })
  assert(#executed_commands <= before + 1, "a space card click runs at most one command")
  return executed_commands[before + 1]
end

local occupied = space_focus_command(3)
local display_focus = occupied and occupied:find("-m display --focus 2", 1, true)
local window_focus = occupied and occupied:find("-m window --focus 302 || ", 1, true)
assert(display_focus and window_focus and display_focus < window_focus,
       "a space with windows focuses its display, then its first window")
assert(occupied:find("switch_desktop' 3", 1, true),
       "a window focus that fails falls back to the desktop shortcut")

-- Space 5 loses its windows; space 4's windows lose their Accessibility references.
yabai_state_output = yabai_state_output
  :gsub("W\t5\t[^\n]*\n", "")
  :gsub("(W\t4\t%d+\t[^\t]*\tfalse\tfalse\tfalse\t)true", "%1false")
added["spaces.state_observer"].subscriptions["display_change"]({})

-- Display two has focus here; space 5 is on display one. Switching to a space
-- without a window would leave focus on display two.
local empty = space_focus_command(5)
local empty_display_focus = empty and empty:find("-m display --focus 1", 1, true)
local empty_switch = empty and empty:find("switch_desktop' 5", 1, true)
assert(empty_display_focus and empty_switch and empty_display_focus < empty_switch
    and not empty:find("window --focus", 1, true),
       "an empty space focuses its display, then presses its desktop shortcut")
local unreferenced = space_focus_command(4)
assert(unreferenced and unreferenced:find("switch_desktop' 4", 1, true)
    and not unreferenced:find("window --focus", 1, true),
       "a space whose windows yabai cannot focus uses its desktop shortcut")
assert(space_focus_command(99) == nil, "a space that does not exist is ignored")

print("spaces toggle tests passed")
