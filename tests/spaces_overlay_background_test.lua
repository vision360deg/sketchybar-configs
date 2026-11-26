package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded.colors = {
  transparent = 0,
  grey = 1,
  bg1 = 2,
  with_alpha = function(color) return color end,
}
package.loaded.icons = { switch = { on = "on", off = "off" } }
package.loaded.settings = {
  spaces_overlay_width = 420,
  spaces_fallback_width = 420,
  font = { style_map = { Heavy = "Heavy", Semibold = "Semibold", Black = "Black" } },
}
package.loaded["helpers.app_icons"] = { Default = "?" }

local added = {}
local default_background = {
  border_width = 2,
  border_color = 3,
  image = { drawing = true, corner_radius = 9 },
}

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
    local origin_x = 10
    local width = self.options.width or 1
    if self.name:match("^spaces%.indicator") then
      origin_x, width = 430, 29
    elseif self.name == "front_app" then
      origin_x, width = 459, 70
    elseif self.name == "spaces.right_boundary" then
      origin_x, width = 900, 1
    end
    return {
      bounding_rects = {
        ["1"] = { origin = { origin_x, 2 }, size = { width, 26 } },
      },
    }
  end

  return item
end

_G.sbar = {
  add = function(_, name, options)
    if type(name) == "table" then
      options = name
      name = "anonymous"
    end
    options = options or {}
    local background = {}
    for key, value in pairs(default_background) do background[key] = value end
    for key, value in pairs(options.background or {}) do background[key] = value end
    options.background = background
    local item = new_item(name, options)
    added[name] = item
    return item
  end,
  exec = function(_, callback)
    if callback then callback("1\n1\n") end
  end,
  trigger = function() end,
  delay = function() end,
  animate = function(_, _, callback) callback() end,
}

local spaces = require("items.spaces")
spaces.start(new_item("front_app"), { hide = function() end, show = function() end })

local background = added["spaces.overlay"].options.background
assert(background.border_width == 0, "overlay removes the inherited border width")
assert(background.border_color == 0, "overlay removes the inherited border color")
assert(background.image.drawing == false, "overlay removes the inherited background image")

print("spaces overlay background tests passed")
