local M = {}

local event_name = "mouse_clicked_global"
local started = false
local popup_margin = 4

local function start_provider()
  if started then return end
  started = true
  sbar.add("event", event_name)
  sbar.exec(
    "killall popup_click >/dev/null 2>&1; "
      .. "$CONFIG_DIR/helpers/event_providers/popup_mouse_click/bin/popup_click"
  )
end

local function is_visible_popup(owner)
  local ok, result = pcall(function() return owner:query() end)
  if not ok or not result or not result.popup then return false end
  return result.popup.drawing == "on" or result.popup.drawing == true
end

local function each_rect(item, callback)
  if not item then return end
  local ok, result = pcall(function() return item:query() end)
  if not ok or not result or not result.bounding_rects then return end

  for _, rect in pairs(result.bounding_rects) do
    local origin = rect.origin
    local size = rect.size
    if origin and size and origin[1] > -9000 and size[1] > 0 and size[2] > 0 then
      callback(origin[1], origin[2], size[1], size[2])
    end
  end
end

local function contains_item(item, x, y)
  local contains = false
  each_rect(item, function(left, top, width, height)
    if x >= left and x <= left + width and y >= top and y <= top + height then
      contains = true
    end
  end)
  return contains
end

local function popup_bounds(items)
  local left, top, right, bottom
  for _, item in ipairs(items or {}) do
    each_rect(item, function(x, y, width, height)
      left = left and math.min(left, x) or x
      top = top and math.min(top, y) or y
      right = right and math.max(right, x + width) or x + width
      bottom = bottom and math.max(bottom, y + height) or y + height
    end)
  end
  return left, top, right, bottom
end

local function contains_popup(items, x, y)
  local left, top, right, bottom = popup_bounds(items)
  if not left then return false end
  return x >= left - popup_margin
    and x <= right + popup_margin
    and y >= top - popup_margin
    and y <= bottom + popup_margin
end

function M.register(owner, popup_items, dismiss)
  start_provider()

  owner:subscribe(event_name, function(env)
    if not is_visible_popup(owner) then return end

    local x = tonumber(env.MOUSE_X)
    local y = tonumber(env.MOUSE_Y)
    if not x or not y then return end

    local items = type(popup_items) == "function" and popup_items() or popup_items
    if contains_item(owner, x, y) or contains_popup(items, x, y) then return end
    dismiss()
  end)
end

return M
