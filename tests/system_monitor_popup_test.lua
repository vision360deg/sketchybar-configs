package.path = "./?.lua;./?/init.lua;" .. package.path

local controllers = {}

local function new_controller(key)
  local controller = {
    key = key,
    names = { "widgets.system_monitor." .. key },
  }

  function controller.set_visible() end
  function controller.subscribe() end

  controllers[key] = controller
  return controller
end

for _, key in ipairs({ "cpu", "memory", "energy", "disk", "network" }) do
  package.preload["items.widgets." .. key] = function()
    return { new = function() return new_controller(key) end }
  end
end

package.preload.colors = function()
  return { white = 1, grey = 2, bg1 = 3 }
end

package.preload.icons = function()
  return {
    cpu = "cpu",
    wifi = { up_down = "network" },
    system_monitor = {
      cpu = "cpu",
      memory = "memory",
      energy = "energy",
      disk = "disk",
      network = "network",
      activity_monitor = "activity_monitor",
    },
  }
end

package.preload.settings = function()
  return { group_paddings = 5 }
end

package.preload["helpers.system_metrics"] = function()
  return { valid_metric = function(key) return controllers[key] ~= nil end }
end

package.preload["helpers.activity_monitor"] = function()
  return { open = function() end }
end

local bracket

sbar = {}

function sbar.add(kind, name)
  local item = { name = name, subscriptions = {} }

  function item:set(properties)
    self.last_set = properties
  end

  function item:subscribe(event, callback)
    self.subscriptions[event] = callback
  end

  function item:query()
    return { popup = { drawing = "on" } }
  end

  if kind == "bracket" then bracket = item end
  return item
end

function sbar.exec(_, callback)
  if callback then callback("") end
end

require("items.widgets.system_monitor")
bracket.last_set = nil

-- popup_manager closes the popup on a mouse-down outside the bracket and its popup.
local outside_click = bracket.subscriptions[require("helpers.popup_manager").click_event]
assert(outside_click, "the system monitor must close its popup on an outside click")

outside_click({ MOUSE_X = "5000", MOUSE_Y = "5000" })

assert(bracket.last_set, "outside click must update the popup")
assert(bracket.last_set.popup.drawing == false, "outside click must close the popup")

print("system monitor popup dismissal: ok")
