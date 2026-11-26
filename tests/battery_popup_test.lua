package.path = "./?.lua;./?/init.lua;" .. package.path

package.preload.icons = function()
  return { battery = { _0 = "0", _25 = "25", _50 = "50", _75 = "75", _100 = "100", charging = "charging" } }
end

package.preload.colors = function()
  return { red = 1, orange = 2, yellow = 3, green = 4, white = 5, bg1 = 6 }
end

package.preload.settings = function()
  return { font = { numbers = "numbers", style_map = { Bold = "Bold" } } }
end

local battery

sbar = {}

function sbar.add(kind, name)
  local item = { name = name, subscriptions = {} }

  function item:set(properties)
    self.last_set = properties
  end

  function item:query()
    return { popup = { drawing = "on" } }
  end

  function item:subscribe(event, callback)
    if type(event) == "table" then
      for _, event_name in ipairs(event) do self.subscriptions[event_name] = callback end
    else
      self.subscriptions[event] = callback
    end
  end

  if not battery then battery = item end
  return item
end

function sbar.exec(_, callback)
  if callback then callback("") end
end

require("items.widgets.battery")
battery.last_set = nil

-- popup_manager closes the popup on a mouse-down outside the battery and its popup.
local outside_click = battery.subscriptions[require("helpers.popup_manager").click_event]
assert(outside_click, "battery must close its popup on an outside click")

outside_click({ MOUSE_X = "5000", MOUSE_Y = "5000" })

assert(battery.last_set, "outside click must update the battery popup")
assert(battery.last_set.popup.drawing == false, "outside click must close the battery popup")

print("battery popup dismissal: ok")
