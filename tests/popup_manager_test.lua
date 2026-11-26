package.path = "./?.lua;./?/init.lua;" .. package.path

local added_events = {}
local executed = {}

sbar = {
  add = function(kind, name)
    if kind == "event" then added_events[name] = true end
  end,
  exec = function(command)
    table.insert(executed, command)
  end,
}

local function item(rect, popup_drawing)
  local subscriptions = {}
  return {
    subscriptions = subscriptions,
    query = function()
      return {
        popup = { drawing = popup_drawing },
        bounding_rects = {
          main = {
            origin = { rect.x, rect.y },
            size = { rect.width, rect.height },
          },
        },
      }
    end,
    subscribe = function(_, event, callback)
      subscriptions[event] = callback
    end,
  }
end

local owner = item({ x = 100, y = 0, width = 40, height = 28 }, "on")
local row_one = item({ x = 90, y = 32, width = 120, height = 30 })
local row_two = item({ x = 90, y = 62, width = 120, height = 30 })
local dismissals = 0

local popup_manager = require("helpers.popup_manager")
popup_manager.register(owner, { row_one, row_two }, function()
  dismissals = dismissals + 1
end)

assert(added_events.mouse_clicked_global, "manager registers the global click event")
assert(#executed == 1 and executed[1]:find("popup_mouse_click"), "manager starts the click provider once")

local click = owner.subscriptions.mouse_clicked_global
assert(click, "owner subscribes to global clicks")

click({ MOUSE_X = "110", MOUSE_Y = "10" })
assert(dismissals == 0, "clicking the owner must not dismiss its popup")

click({ MOUSE_X = "100", MOUSE_Y = "50" })
assert(dismissals == 0, "clicking a popup row must not dismiss its popup")

click({ MOUSE_X = "95", MOUSE_Y = "31" })
assert(dismissals == 0, "clicking the popup background gap must not dismiss its popup")

click({ MOUSE_X = "40", MOUSE_Y = "200" })
assert(dismissals == 1, "clicking outside must dismiss the popup")

local second_owner = item({ x = 200, y = 0, width = 40, height = 28 }, "off")
popup_manager.register(second_owner, {}, function()
  dismissals = dismissals + 1
end)
assert(#executed == 1, "manager does not launch duplicate click providers")
second_owner.subscriptions.mouse_clicked_global({ MOUSE_X = "0", MOUSE_Y = "0" })
assert(dismissals == 1, "closed popups ignore global clicks")

print("popup manager tests passed")
