local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local app_icons = require("helpers.app_icons")

local space_count = 10
local safety_gap = 12
local default_space_width = 50
local space_item_padding = 1
local spaces = {}
local space_paddings = {}
local space_widths = {}
local space_visibility = {}
local viewport_start = 1
local viewport_end = space_count
local viewport_width = settings.spaces_fallback_width
local viewport_started = false
local spaces_indicator
local right_boundary
local front_app_item
local horizontal_scroll_event = "spaces_horizontal_scroll"
local horizontal_scroll_accumulator = 0

sbar.add("event", horizontal_scroll_event)

local left_boundary = sbar.add("item", "spaces.left_boundary", {
  width = 0,
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  label = { drawing = false },
})

local function positive_number(value)
  return type(value) == "number" and value > 0 and value or nil
end

local function horizontal_scroll_threshold()
  return positive_number(settings.spaces_horizontal_scroll_threshold) or 8
end

local function horizontal_scroll_inverted()
  return settings.spaces_horizontal_scroll_inverted == true
end

local function query_item(item)
  if not item then return nil end

  local ok, result = pcall(function()
    return item:query()
  end)
  return ok and result or nil
end

local function active_display_key()
  local result = query_item(front_app_item)
  if not result or not result.bounding_rects then return nil end

  for display, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.origin[1] > -9000 then
      return display
    end
  end
end

local function bounding_rect(item)
  local result = query_item(item)
  if not result or not result.bounding_rects then return nil end

  local display = active_display_key()
  if display and result.bounding_rects[display] then
    return result.bounding_rects[display]
  end

  for _, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.origin[1] > -9000 then
      return rect
    end
  end
end

local function geometry_width(item)
  local result = bounding_rect(item)
  return result and result.size and positive_number(result.size[1]) or nil
end

local function geometry_position(item)
  local result = bounding_rect(item)
  return result and result.origin and positive_number(result.origin[1]) or nil
end

local function measure_space(index)
  local measured = geometry_width(spaces[index])
  if measured then
    space_widths[index] = measured + settings.group_paddings + 2 * space_item_padding
  end
  return space_widths[index] or default_space_width
end

local function automatic_width()
  local left = geometry_position(left_boundary)
  local right = geometry_position(right_boundary)
  local indicator_width = geometry_width(spaces_indicator) or 0
  local front_app_width = geometry_width(front_app_item) or 0

  if not left or not right or right <= left then
    return nil
  end

  return right - left - indicator_width - front_app_width - safety_gap
end

local function effective_width()
  local available = positive_number(automatic_width()) or viewport_width
  local configured = positive_number(settings.spaces_max_width)
  viewport_width = configured and math.min(available, configured) or available
  return viewport_width
end

local function spaces_are_enabled()
  if not spaces_indicator then return true end

  local ok, enabled = pcall(function()
    return spaces_indicator:query().icon.value == icons.switch.on
  end)
  return not ok or enabled
end

local function point_in_spaces_viewport(x, y)
  if not spaces_are_enabled() then return false end

  local left = bounding_rect(left_boundary)
  local front_app = bounding_rect(front_app_item)
  if not left or not front_app then return false end
  if not left.origin or not left.size then return false end
  if not front_app.origin or not front_app.size then return false end

  local left_x = left.origin[1]
  local right_x = front_app.origin[1] + front_app.size[1]
  local top_y = left.origin[2]
  local bottom_y = top_y + left.size[2]

  return x >= left_x and x <= right_x and y >= top_y and y <= bottom_y
end

local function set_space_visible(index, visible)
  if space_visibility[index] == visible then return end

  space_visibility[index] = visible
  spaces[index]:set({ drawing = visible })
  space_paddings[index]:set({ drawing = visible })
end

local function invalidate_space_visibility()
  for index = 1, space_count do
    space_visibility[index] = nil
  end
end

local function apply_viewport()
  if not spaces_are_enabled() then return end

  local limit = effective_width()
  local used = 0
  local last = viewport_start
  local visible_spaces = {}

  for index = viewport_start, space_count do
    local width = measure_space(index)
    if index > viewport_start and used + width > limit then
      break
    end

    visible_spaces[index] = true
    used = used + width
    last = index
  end

  for index = 1, space_count do
    set_space_visible(index, visible_spaces[index] == true)
  end

  viewport_end = last
end

local function schedule_viewport_update(delay)
  sbar.delay(delay or 0.05, apply_viewport)
end

local reveal_generation = 0

local function start_for_revealed_space(index)
  local limit = effective_width()
  local start = index
  local used = measure_space(index)

  while start > 1 do
    local previous_width = measure_space(start - 1)
    if used + previous_width > limit then break end
    start = start - 1
    used = used + previous_width
  end

  return start
end

local function reveal_space(index, force)
  if not force and index >= viewport_start and index <= viewport_end then
    apply_viewport()
    return
  end

  reveal_generation = reveal_generation + 1
  local generation = reveal_generation
  viewport_start = index
  apply_viewport()

  local function settle(remaining_passes)
    if generation ~= reveal_generation then return end

    viewport_start = start_for_revealed_space(index)
    apply_viewport()
    if remaining_passes > 1 then
      sbar.delay(0.05, function() settle(remaining_passes - 1) end)
    end
  end

  sbar.delay(0.05, function() settle(2) end)
end

local function scroll_viewport(delta, target)
  if delta < 0 then
    target = target or viewport_end + 1
    if target > space_count then return false end
    reveal_space(target, true)
  elseif delta > 0 and viewport_start > 1 then
    reveal_space(viewport_start - 1, true)
  else
    return false
  end

  return true
end

local function same_direction(first, second)
  return (first < 0 and second < 0) or (first > 0 and second > 0)
end

local function handle_horizontal_scroll(env)
  local delta = tonumber(env.SCROLL_DELTA) or 0
  local x = tonumber(env.MOUSE_X)
  local y = tonumber(env.MOUSE_Y)

  if delta == 0 or not x or not y or not point_in_spaces_viewport(x, y) then
    horizontal_scroll_accumulator = 0
    return
  end

  if horizontal_scroll_inverted() then
    delta = -delta
  end

  if horizontal_scroll_accumulator ~= 0
      and not same_direction(horizontal_scroll_accumulator, delta) then
    horizontal_scroll_accumulator = 0
  end

  horizontal_scroll_accumulator = horizontal_scroll_accumulator + delta
  local threshold = horizontal_scroll_threshold()

  local right_target = viewport_end
  while math.abs(horizontal_scroll_accumulator) >= threshold do
    local direction = horizontal_scroll_accumulator < 0 and -1 or 1
    local target
    if direction < 0 then
      right_target = right_target + 1
      target = right_target
    end

    if not scroll_viewport(direction, target) then
      horizontal_scroll_accumulator = 0
      return
    end
    horizontal_scroll_accumulator = horizontal_scroll_accumulator - direction * threshold
  end
end

for i = 1, space_count, 1 do
  local space = sbar.add("space", "space." .. i, {
    space = i,
    icon = {
      font = { family = settings.font.numbers },
      string = i,
      padding_left = 15,
      padding_right = 8,
      color = colors.white,
      highlight_color = colors.red,
    },
    label = {
      padding_right = 20,
      color = colors.grey,
      highlight_color = colors.white,
      font = "sketchybar-app-font:Regular:16.0",
      y_offset = -1,
    },
    padding_right = space_item_padding,
    padding_left = space_item_padding,
    background = {
      color = colors.bg1,
      border_width = 1,
      height = 24,
      border_color = colors.black,
    },
    popup = { background = { border_width = 5, border_color = colors.black } }
  })

  spaces[i] = space

  local space_bracket = sbar.add("bracket", { space.name }, {
    background = {
      color = colors.transparent,
      border_color = colors.bg2,
      height = 26,
      border_width = 1
    }
  })

  space_paddings[i] = sbar.add("space", "space.padding." .. i, {
    space = i,
    script = "",
    width = settings.group_paddings,
  })

  local space_popup = sbar.add("item", {
    position = "popup." .. space.name,
    padding_left = 5,
    padding_right = 0,
    background = {
      drawing = true,
      image = {
        corner_radius = 9,
        scale = 0.2
      }
    }
  })

  space:subscribe("space_change", function(env)
    local selected = env.SELECTED == "true"
    space:set({
      icon = { highlight = selected, },
      label = { highlight = selected },
      background = { border_color = selected and colors.black or colors.bg2 }
    })
    space_bracket:set({
      background = { border_color = selected and colors.grey or colors.bg2 }
    })

    if selected then
      reveal_space(i)
    end
  end)

  space:subscribe("mouse.clicked", function(env)
    if env.BUTTON == "other" then
      space_popup:set({ background = { image = "space." .. env.SID } })
      space:set({ popup = { drawing = "toggle" } })
    else
      local op = (env.BUTTON == "right") and "--destroy" or "--focus"
      sbar.exec("yabai -m space " .. op .. " " .. env.SID)
    end
  end)

  space:subscribe("mouse.scrolled", function(env)
    scroll_viewport(tonumber(env.SCROLL_DELTA) or 0)
  end)

  space:subscribe("mouse.exited", function(_)
    space:set({ popup = { drawing = false } })
  end)
end

local space_window_observer = sbar.add("item", {
  drawing = false,
  updates = true,
})

space_window_observer:subscribe(horizontal_scroll_event, handle_horizontal_scroll)

spaces_indicator = sbar.add("item", "spaces.indicator", {
  padding_left = -3,
  padding_right = 0,
  icon = {
    padding_left = 8,
    padding_right = 9,
    color = colors.grey,
    string = icons.switch.on,
  },
  label = {
    width = 0,
    padding_left = 0,
    padding_right = 8,
    string = "Spaces",
    color = colors.bg1,
  },
  background = {
    color = colors.with_alpha(colors.grey, 0.0),
    border_color = colors.with_alpha(colors.bg1, 0.0),
  }
})

space_window_observer:subscribe("space_windows_change", function(env)
  local icon_line = ""
  local no_app = true
  for app, _ in pairs(env.INFO.apps) do
    no_app = false
    local lookup = app_icons[app]
    local icon = ((lookup == nil) and app_icons["Default"] or lookup)
    icon_line = icon_line .. icon
  end

  if no_app then
    icon_line = ""
  end

  local index = tonumber(env.INFO.space)
  if not index or not spaces[index] then return end

  sbar.animate("tanh", 10, function()
    spaces[index]:set({ label = icon_line })
  end)
  schedule_viewport_update(0.15)
end)

spaces_indicator:subscribe("swap_menus_and_spaces", function(_)
  local currently_on = spaces_indicator:query().icon.value == icons.switch.on
  spaces_indicator:set({
    icon = currently_on and icons.switch.off or icons.switch.on
  })

  if not currently_on then
    invalidate_space_visibility()
    schedule_viewport_update()
  end
end)

spaces_indicator:subscribe("mouse.entered", function(_)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic" }
    })
  end)
  schedule_viewport_update(0.5)
end)

spaces_indicator:subscribe("mouse.exited", function(_)
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0, }
    })
  end)
  schedule_viewport_update(0.5)
end)

spaces_indicator:subscribe("mouse.clicked", function(_)
  sbar.trigger("swap_menus_and_spaces")
end)

local function start(front_app)
  if viewport_started then return end

  viewport_started = true
  front_app_item = front_app
  right_boundary = sbar.add("item", "spaces.right_boundary", {
    position = "right",
    width = 1,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
    background = { color = colors.transparent },
  })

  right_boundary:subscribe({
    "display_change",
    "front_app_switched",
    "media_change",
    "volume_change",
    "wifi_change",
    "power_source_change",
    "network_update",
    "system_woke",
  }, function(_)
    schedule_viewport_update()
  end)

  sbar.exec(
    "killall horizontal_scroll >/dev/null 2>&1; "
      .. "$CONFIG_DIR/helpers/event_providers/horizontal_scroll/bin/horizontal_scroll &"
  )

  schedule_viewport_update()
end

return { start = start }
