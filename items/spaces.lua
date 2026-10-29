local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local space_labels = require("helpers.space_labels")
local space_windows = require("helpers.space_windows")

local popup_manager = require("helpers.popup_manager")

local overlay_config = {}
local config_dir = os.getenv("CONFIG_DIR") or "."
local recovery_script = config_dir .. "/helpers/spaces_overlay/recover_if_stale.sh"
local config_ok, loaded_config = pcall(dofile, config_dir .. "/helpers/spaces_overlay/config.lua")
if config_ok and type(loaded_config) == "table" then
  overlay_config = loaded_config
end

local space_capacity = 32
local indicator_capacity = 8
local active_space_count
local space_count_event = "spaces_count_changed"
local space_order_event = "spaces_order_changed"
local window_focus_event = "spaces_window_focus_changed"
local window_destroyed_event = "spaces_window_destroyed"
local safety_gap = 12
local service_name = "com.vision3.sketchybar.spaces"
local yabai_command = "export USER=$(/usr/bin/id -un); /opt/homebrew/bin/yabai"
local sync_event = "spaces_overlay_sync"
local labels = {}
local selected_space = 1
local revision = 0
local space_displays = {}
local display_frames = {}
local display_panel_widths = {}
local visible = true
local content_sync_generation = 0
local geometry_sync_generation = 0
local indicators = {}
local indicator_display_order = {}
local indicator_display_map = {}
local indicator_paddings = {}
local indicator_hovered = {}
local indicator_probe
local indicator_probe_display
local indicator_measurement_display
local indicator_layout_generation = 0
local expanded_indicator_width
local indicator_collapsed_width
local indicator_measurement_phase = 0
local indicator_label_delta = 50
local menu_controller
local last_rect
local front_app_controller
local front_app_item
local display_apps = {}
local right_boundary
local started = false
local window_records = space_windows.rebuild("", space_capacity)
local foreground_window_ids = {}
local refresh_generation = 0
local schedule_geometry_sync

for index = 1, space_capacity do
  labels[index] = {}
end

sbar.add("event", sync_event)
sbar.add("event", space_count_event)
sbar.add("event", space_order_event)
sbar.add("event", window_focus_event)
sbar.add("event", window_destroyed_event)

local function positive_number(value)
  return type(value) == "number" and value > 0 and value or nil
end

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function query_item(item)
  if not item then return nil end
  local ok, result = pcall(function() return item:query() end)
  return ok and result or nil
end

local display_index_for_rect
local sketchy_display_index

local function active_display_key(item)
  local result = query_item(item)
  if not result or not result.bounding_rects then return nil end

  local active_yabai = space_displays[selected_space]
  if active_yabai then
    for display, rect in pairs(result.bounding_rects) do
      if rect.origin and rect.origin[1] > -9000 then
        local mapped = display_index_for_rect({
          origin = rect.origin,
          size = rect.size,
        })
        if mapped == active_yabai then return display end
      end
    end
  end

  for display, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.origin[1] > -9000 then
      return display
    end
  end
end

local function bounding_rect(item)
  local result = query_item(item)
  if not result or not result.bounding_rects then return nil end

  local display = active_display_key(item)
  if display and result.bounding_rects[display] then
    local rect = result.bounding_rects[display]
    if rect.origin and rect.origin[1] > -9000 then return rect end
  end

  for _, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.origin[1] > -9000 then return rect end
  end
end

local long_press_seconds = 2
local long_press_generation = 0
local long_press_ready = false

local function cancel_long_press()
  long_press_generation = long_press_generation + 1
  long_press_ready = false
end

local function consume_long_press()
  local triggered = long_press_ready
  cancel_long_press()
  return triggered
end

local bar_click_slop = 1
local fallback_bar_height = 28
local cached_bar_height

local function bar_height()
  if cached_bar_height then return cached_bar_height end
  local ok, result = pcall(function() return sbar.query("bar") end)
  local geometry = ok and result and result.geometry
  cached_bar_height = geometry and tonumber(geometry.height) or fallback_bar_height
  return cached_bar_height
end

-- SketchyBar only reports item clicks, so use the global mouse-down coordinates
-- to focus the clicked display's bar. Each display's Spaces indicator marks the
-- vertical band of that display's bar without duplicating SketchyBar geometry.
local function bar_display_for_point(x, y)
  local display_index = display_index_for_rect({
    origin = { x, y },
    size = { 1, 1 },
  })
  if not display_index then return nil end
  local frame = display_frames[display_index]
  if frame and frame.focused then return nil end

  local sketchy_index = sketchy_display_index(display_index)
  local item = sketchy_index and indicators[sketchy_index]
  if not item then return nil end

  local rect = bounding_rect(item)
  if not rect or not rect.origin or not rect.size then return nil end

  local center_y = rect.origin[2] + rect.size[2] / 2
  local half_height = bar_height() / 2
  local top = center_y - half_height - bar_click_slop
  local bottom = center_y + half_height + bar_click_slop
  if y < top or y > bottom then return nil end

  return display_index
end

local function focus_bar_display(display_index)
  if not display_index then return end

  sbar.exec(yabai_command .. " -m display --focus " .. display_index)
end

-- The popup click provider already polls the global mouse state. Reuse its
-- mouse-down event so a normal Spaces click can be told apart from a long press.
popup_manager.ensure_provider()
local press_observer = sbar.add("item", "spaces.press_observer", {
  drawing = false,
  updates = true,
})
press_observer:subscribe(popup_manager.click_event, function(env)
  local x = tonumber(env.MOUSE_X)
  local y = tonumber(env.MOUSE_Y)
  if x and y then
    focus_bar_display(bar_display_for_point(x, y))
  end

  cancel_long_press()
  if env.BUTTON ~= "left" then return end
  local generation = long_press_generation
  sbar.delay(long_press_seconds, function()
    if generation ~= long_press_generation then return end
    long_press_ready = true
  end)
end)

local function geometry_width(item)
  local rect = bounding_rect(item)
  return rect and rect.size and positive_number(rect.size[1]) or nil
end

local function geometry_position(item)
  local rect = bounding_rect(item)
  return rect and rect.origin and rect.origin[1] or nil
end

local function hex_encode(value)
  return (value:gsub(".", function(character)
    return string.format("%02x", string.byte(character))
  end))
end

local function encoded_labels()
  local encoded = {}
  for index = 1, active_space_count or 0 do
    encoded[index] = hex_encode(space_labels.serialize(labels[index]))
  end
  return table.concat(encoded, ",")
end

local function encoded_window_ids()
  return space_windows.serialize_ids(window_records, active_space_count or 0)
end

local function encoded_foreground_ids()
  return space_windows.serialize_foreground_ids(
    foreground_window_ids,
    active_space_count or 0
  )
end

local configured_overlay_width = positive_number(settings.spaces_overlay_width)
  or positive_number(settings.spaces_max_width)
local overlay_width = configured_overlay_width
  or positive_number(settings.spaces_fallback_width)
  or 420
local current_overlay_width = overlay_width

local overlay = sbar.add("item", "spaces.overlay", {
  width = overlay_width,
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  label = { drawing = false },
  background = {
    drawing = true,
    color = colors.transparent,
    height = 26,
    border_width = 0,
    border_color = colors.transparent,
    image = { drawing = false },
  },
})

local transport = sbar.add("item", "spaces.overlay.transport", {
  drawing = true,
  width = 0,
  padding_left = 0,
  padding_right = 0,
  icon = { drawing = false },
  label = { drawing = false },
  background = { drawing = false },
  mach_helper = service_name,
})

transport:subscribe(sync_event, function(_) end)
transport:set({ mach_helper = service_name, script = "" })

local encode_display_groups
local ensure_indicators
local update_indicator_offset

local function sync_snapshot(prefer_cached_rect)
  if not active_space_count then return end
  local rect = prefer_cached_rect and last_rect or bounding_rect(overlay)
  if rect and rect.origin and rect.size then
    last_rect = rect
  elseif not prefer_cached_rect then
    rect = last_rect
  else
    rect = bounding_rect(overlay)
    if rect and rect.origin and rect.size then last_rect = rect end
  end
  if not rect or not rect.origin or not rect.size then return end

  revision = revision + 1
  local snapshot_env = {
    REVISION = tostring(revision),
    VISIBLE = visible and "true" or "false",
    X = tostring(rect.origin[1]),
    Y = tostring(rect.origin[2]),
    WIDTH = tostring(rect.size[1]),
    HEIGHT = tostring(rect.size[2]),
    SELECTED = tostring(selected_space),
    LABELS = encoded_labels(),
    WINDOW_IDS = encoded_window_ids(),
    FOREGROUND_IDS = encoded_foreground_ids(),
    REARRANGE_SPACES = overlay_config.rearrange_spaces == true and "true" or "false",
  }
  local encoded_displays = encode_display_groups(rect)
  if encoded_displays then
    snapshot_env.DISPLAYS = encoded_displays
  end
  sbar.trigger(sync_event, snapshot_env)
  update_indicator_offset()
end

local function schedule_sync(delay)
  content_sync_generation = content_sync_generation + 1
  local generation = content_sync_generation
  sbar.delay(delay or 0.05, function()
    if generation == content_sync_generation then sync_snapshot() end
  end)
end

local function refresh_displays()
  sbar.exec(
    yabai_command .. " -m query --displays"
      .. " | /opt/homebrew/bin/jq -r '.[] | [(.index // 1), (.frame.x // 0), (.frame.y // 0), (.frame.w // 0), (.frame.h // 0), (.[\"has-focus\"] // false)] | @tsv'",
    function(output)
      local frames = {}
      for line in (output or ""):gmatch("[^\r\n]+") do
        local index_text, x_text, y_text, width_text, height_text =
          line:match("^(%d+)\t(%-?[%d.]+)\t(%-?[%d.]+)\t(%-?[%d.]+)\t(%-?[%d.]+)")
        local focused_text = line:match("\t(%a+)$")
        local index = tonumber(index_text)
        local x = tonumber(x_text)
        local y = tonumber(y_text)
        local width = tonumber(width_text)
        local height = tonumber(height_text)
        if index and x and y and width and height and width > 0 and height > 0 then
          frames[index] = {
            x = x,
            y = y,
            width = width,
            height = height,
            focused = focused_text == "true" or focused_text == "1",
          }
        end
      end
      if next(frames) then
        display_frames = frames
        ensure_indicators()
        schedule_sync()
      end
    end
  )
end

local function bounding_rects_by_display(item)
  local result = query_item(item)
  if not result or not result.bounding_rects then return nil end

  local rects = {}
  for _, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.size and rect.origin[1] > -9000 and rect.size[1] > 0 then
      rects[#rects + 1] = { origin = rect.origin, size = rect.size }
    end
  end
  return rects
end

display_index_for_rect = function(rect)
  local center_x = rect.origin[1] + rect.size[1] / 2
  local center_y = rect.origin[2] + rect.size[2] / 2
  for index, frame in pairs(display_frames) do
    if center_x >= frame.x and center_x < frame.x + frame.width
        and center_y >= frame.y and center_y < frame.y + frame.height then
      return index
    end
  end
  return nil
end

local function overlay_frame_for_display(display_index, rect, bar_display)
  local frame = display_frames[display_index]
  if not frame then return nil end
  local main_frame = display_frames[bar_display]
  if not main_frame then return nil end

  local top_gap = rect.origin[2] - main_frame.y
  local bottom_gap = main_frame.y + main_frame.height - (rect.origin[2] + rect.size[2])
  local overlay_y
  if top_gap <= bottom_gap then
    overlay_y = frame.y + top_gap
  else
    overlay_y = frame.y + frame.height - bottom_gap - rect.size[2]
  end
  overlay_y = math.max(frame.y, math.min(overlay_y, frame.y + frame.height - rect.size[2]))
  local overlay_width = math.min(rect.size[1], frame.width)
  local left_offset = rect.origin[1] - main_frame.x
  local overlay_x = frame.x + left_offset
  overlay_x = math.max(frame.x, math.min(overlay_x, frame.x + frame.width - overlay_width))
  return {
    origin = { overlay_x, overlay_y },
    size = { overlay_width, rect.size[2] },
  }
end

local minimum_overlay_width = 54

local function display_content_width(spaces)
  local display_labels = {}
  for position, space in ipairs(spaces) do
    display_labels[position] = labels[space] or {}
  end
  return positive_number(space_labels.content_width(display_labels, #spaces)) or 0
end

local function display_group_payload(display_index, rect, bar_display, measured_rect)
  local spaces = {}
  for space = 1, active_space_count do
    if (space_displays[space] or bar_display) == display_index then
      spaces[#spaces + 1] = space
    end
  end

  local label_parts = {}
  local window_id_parts = {}
  local foreground_parts = {}
  for position, space in ipairs(spaces) do
    label_parts[position] = hex_encode(space_labels.serialize(labels[space]))
    local ids = {}
    for _, record in ipairs(window_records[space] or {}) do
      ids[#ids + 1] = tostring(record.id)
    end
    window_id_parts[position] = table.concat(ids, ":")
    foreground_parts[position] = tostring(foreground_window_ids[space] or "")
  end

  local selected = 0
  for _, space in ipairs(spaces) do
    if space == selected_space then selected = space end
  end

  local frame = measured_rect or overlay_frame_for_display(display_index, rect, bar_display)
  local overlay_width = configured_overlay_width
    or math.max(display_content_width(spaces), minimum_overlay_width)
  overlay_width = math.min(overlay_width, frame.size[1])
  display_panel_widths[display_index] = overlay_width
  frame = {
    origin = { frame.origin[1], frame.origin[2] },
    size = { overlay_width, frame.size[2] },
  }
  return table.concat({
    tostring(display_index),
    tostring(frame.origin[1]),
    tostring(frame.origin[2]),
    tostring(frame.size[1]),
    tostring(frame.size[2]),
    tostring(selected),
    table.concat(spaces, ","),
    table.concat(label_parts, ","),
    table.concat(window_id_parts, ","),
    table.concat(foreground_parts, ","),
  }, "|")
end

encode_display_groups = function(rect)
  local sorted = {}
  for index in pairs(display_frames) do
    sorted[#sorted + 1] = index
  end
  table.sort(sorted)
  if #sorted == 0 then return nil end

  local measured = {}
  local measured_rects = bounding_rects_by_display(overlay)
  if measured_rects then
    for _, entry in ipairs(measured_rects) do
      local entry_rect = { origin = entry.origin, size = entry.size }
      local index = display_index_for_rect(entry_rect)
      if index then measured[index] = entry_rect end
    end
  end

  local bar_display = display_index_for_rect(rect) or sorted[1]

  local groups = {}
  for _, index in ipairs(sorted) do
    groups[#groups + 1] = display_group_payload(index, rect, bar_display, measured[index])
  end
  return table.concat(groups, ";")
end

sketchy_display_index = function(yabai_index)
  if not yabai_index or yabai_index < 1 then return nil end
  local sorted = {}
  for index in pairs(display_frames) do
    sorted[#sorted + 1] = index
  end
  table.sort(sorted)
  for rank, index in ipairs(sorted) do
    if index == yabai_index then return rank end
  end
  return yabai_index
end

local function set_display_app(display_index, app)
  if not display_index or display_index < 1 or not app or app == "" then return end
  display_apps[display_index] = app
  local sketchy_index = sketchy_display_index(display_index)
  if front_app_controller and front_app_controller.set_app then
    front_app_controller.set_app(sketchy_index, app)
  elseif front_app_item then
    front_app_item:set({ label = { string = app } })
  end
end

local function update_display_apps(records)
  for space = 1, active_space_count or 0 do
    local fallback_display = space_displays[space]
    for _, record in ipairs(records[space] or {}) do
      local display_index = record.display
      if not display_index or display_index < 1 then
        display_index = fallback_display
      end
      if display_index and display_index >= 1 and record.app ~= "" then
        if record.focused or not display_apps[display_index] then
          set_display_app(display_index, record.app)
        end
      end
    end
  end
end

local function refresh_space_labels()
  if not active_space_count then return end

  refresh_generation = refresh_generation + 1
  local generation = refresh_generation
  sbar.exec(
    yabai_command .. " -m query --windows"
      .. " | /opt/homebrew/bin/jq -r '.[] | [(.space // 0), (.id // 0), (.app // \"\"), (.[\"is-minimized\"] // false), (.[\"is-hidden\"] // false), (.[\"has-focus\"] // false), (.[\"has-ax-reference\"] // false), (.display // 0)] | @tsv'",
    function(output)
      if generation ~= refresh_generation then return end
      local records = space_windows.rebuild(output, space_capacity, window_records)
      window_records = records
      foreground_window_ids = space_windows.foreground_ids(
        records,
        space_capacity,
        foreground_window_ids
      )
      update_display_apps(records)
      labels = space_windows.apps(records, space_capacity)
      sync_snapshot(true)
      schedule_geometry_sync()
    end
  )
end

local function refresh_after_window_destroyed()
  refresh_space_labels()
  sbar.delay(0.15, refresh_space_labels)
  sbar.delay(0.4, refresh_space_labels)
end



for index = 1, space_capacity do
  local state_item = sbar.add("space", "spaces.state." .. index, {
    space = index,
    drawing = false,
    updates = true,
    width = 0,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
  })

  state_item:subscribe("space_change", function(env)
    if env.SELECTED == "true" then
      selected_space = index
      refresh_space_labels()
    end
    schedule_sync()
  end)
end

local window_observer = sbar.add("item", "spaces.window_observer", {
  drawing = false,
  updates = true,
})

window_observer:subscribe("space_windows_change", function(env)
  local index = tonumber(env.INFO.space)
  if not index or index < 1 or index > (active_space_count or 0) then return end

  refresh_space_labels()
end)

local foreground_observer = sbar.add("item", "spaces.foreground_observer", {
  drawing = false,
  updates = true,
})

foreground_observer:subscribe({
  "front_app_switched",
  window_focus_event,
}, refresh_space_labels)
foreground_observer:subscribe(window_destroyed_event, refresh_after_window_destroyed)

local space_order_observer = sbar.add("item", "spaces.order_observer", {
  drawing = false,
  updates = true,
})

space_order_observer:subscribe(space_order_event, refresh_space_labels)

-- SketchyBar draws one bar per display. Give every bar its own Spaces toggle so
-- hover state, label measurement, and panel alignment stay local to that display.
local function indicator_options()
  return {
    padding_left = 2,
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
      color = colors.with_alpha(colors.bg1, 0.0),
    },
    background = {
      color = colors.with_alpha(colors.grey, 0.0),
      border_color = colors.with_alpha(colors.bg1, 0.0),
    },
  }
end

local function apply_indicator_hover(display_index, hovered)
  indicator_hovered[display_index] = hovered
  local item = indicators[display_index]
  if not item then return end

  sbar.animate("tanh", 30, function()
    item:set({
      background = {
        color = { alpha = hovered and 1.0 or 0.0 },
        border_color = { alpha = hovered and 1.0 or 0.0 },
      },
      icon = { color = hovered and colors.bg1 or colors.grey },
      label = {
        width = hovered and "dynamic" or 0,
        color = { alpha = hovered and 1.0 or 0.0 },
      },
    })
  end)
end

local function create_indicator(display_index)
  local options = indicator_options()
  options.display = display_index
  options.drawing = false
  options.icon.string = visible and icons.switch.on or icons.switch.off
  local item = sbar.add("item", "spaces.indicator." .. display_index, options)

  item:subscribe("mouse.entered", function(_)
    apply_indicator_hover(display_index, true)
  end)
  item:subscribe("mouse.exited", function(_)
    apply_indicator_hover(display_index, false)
  end)
  item:subscribe("mouse.clicked", function(_)
    if consume_long_press() then
      sbar.exec("/bin/zsh " .. shell_quote(recovery_script))
    else
      sbar.trigger("swap_menus_and_spaces")
    end
  end)

  indicators[display_index] = item
  indicator_hovered[display_index] = false
  indicator_paddings[display_index] = 2
  if not indicator_probe then
    indicator_probe = item
    indicator_probe_display = display_index
  end
  if indicator_measurement_phase >= 3 then
    item:set({ label = { width = 0 } })
  end
  return item
end

-- Create the toggles before the front-app item is loaded so SketchyBar places
-- them directly after the overlay. Displays are resolved asynchronously later.
for display_index = 1, indicator_capacity do
  create_indicator(display_index)
end

local function measurement_indicator()
  for _, display_index in ipairs(indicator_display_order) do
    if not indicator_hovered[display_index] then
      return indicators[display_index], display_index
    end
  end
end

local function indicator_width_for_layout()
  if expanded_indicator_width then return expanded_indicator_width end

  if indicator_probe then
    local width = geometry_width(indicator_probe)
    if width then return width end
  end

  for _, display_index in ipairs(indicator_display_order) do
    local width = geometry_width(indicators[display_index])
    if width then return width end
  end
  return 0
end

local function display_index_for_rect_origin(rect)
  return display_index_for_rect({
    origin = {
      rect.origin[1] + math.min(1, rect.size[1] / 2),
      rect.origin[2] + rect.size[2] / 2,
    },
    size = { 1, 1 },
  })
end

local function rects_by_yabai_display(item)
  local by_display = {}
  for _, entry in ipairs(bounding_rects_by_display(item) or {}) do
    local display_index = display_index_for_rect_origin(entry)
    if display_index and not by_display[display_index] then
      by_display[display_index] = entry
    end
  end
  return by_display
end

local function resolve_indicator_display(sketchy_index, item)
  local by_display = rects_by_yabai_display(item)
  local preferred = indicator_display_map[sketchy_index]
  if preferred and by_display[preferred] then
    return preferred
  end
  if by_display[sketchy_index] then
    indicator_display_map[sketchy_index] = sketchy_index
    return sketchy_index
  end

  local sorted = {}
  for display_index in pairs(by_display) do
    sorted[#sorted + 1] = display_index
  end
  table.sort(sorted)
  local display_index = sorted[1]
  if display_index then
    indicator_display_map[sketchy_index] = display_index
    return display_index
  end

  indicator_display_map[sketchy_index] = nil
  return nil
end

ensure_indicators = function()
  local display_count = 0
  for _ in pairs(display_frames) do
    display_count = display_count + 1
  end
  if display_count == 0 then return end

  local previous_count = #indicator_display_order
  local created = false
  local order = {}
  for display_index = 1, display_count do
    local item = indicators[display_index]
    if not item then
      item = create_indicator(display_index)
      created = true
    end
    item:set({ drawing = true })
    order[#order + 1] = display_index
  end
  indicator_display_order = order
  local order_changed = #order ~= previous_count

  for display_index, item in pairs(indicators) do
    if display_index > display_count then
      item:set({ drawing = false })
      indicator_hovered[display_index] = false
    end
  end

  if not indicator_probe or indicator_probe_display > display_count then
    indicator_probe = indicators[1]
    indicator_probe_display = 1
  end

  if created or order_changed then
    indicator_layout_generation = indicator_layout_generation + 1
    local generation = indicator_layout_generation
    sbar.delay(0.15, function()
      if generation ~= indicator_layout_generation then return end
      update_indicator_offset()
      schedule_geometry_sync(0.05)
    end)
  end
end

-- SketchyBar and yabai index displays independently. Resolve each toggle's real
-- display from its measured rect, then pull it over that display's native panel.
update_indicator_offset = function()
  if not visible then
    for _, display_index in ipairs(indicator_display_order) do
      local item = indicators[display_index]
      if item and (indicator_paddings[display_index] or 2) ~= 2 then
        indicator_paddings[display_index] = 2
        item:set({ padding_left = 2 })
      end
    end
    return
  end

  local overlay_rects = rects_by_yabai_display(overlay)
  for _, sketchy_index in ipairs(indicator_display_order) do
    local item = indicators[sketchy_index]
    if item then
      local yabai_index = resolve_indicator_display(sketchy_index, item)
      local overlay_rect = yabai_index and overlay_rects[yabai_index]
      local panel_width = yabai_index and display_panel_widths[yabai_index]
      local overlay_width = overlay_rect and positive_number(overlay_rect.size[1])
      if overlay_rect and panel_width and overlay_width then
        local pull = math.max(0, overlay_width - panel_width - 4)
        local padding = 2 - pull
        if math.abs((indicator_paddings[sketchy_index] or 2) - padding) > 0.5 then
          indicator_paddings[sketchy_index] = padding
          item:set({ padding_left = padding })
        end
      end
    end
  end
end

local function front_app_layout_width()
  if front_app_controller and front_app_controller.items then
    local max_width = 0
    local display_count = math.max(1, #indicator_display_order)
    for display_index = 1, display_count do
      local item = front_app_controller.items[display_index]
      if item then
        local width = geometry_width(item)
        if width and width > max_width then max_width = width end
      end
    end
    return max_width
  end
  return front_app_item and geometry_width(front_app_item) or 0
end

local function automatic_overlay_width()

  local left = geometry_position(overlay)
  local right = geometry_position(right_boundary)
  local indicator_width = indicator_width_for_layout()
  local front_app_width = front_app_layout_width()
  if not left or not right or right <= left then return nil end

  local available_width
  local rect = bounding_rect(overlay)
  local active_display = rect and display_index_for_rect(rect)
  local active_frame = active_display and display_frames[active_display]
  if active_frame and rect and next(display_frames) then
    local right_inset = active_frame.x + active_frame.width - right
    local left_offset = rect.origin[1] - active_frame.x
    available_width = math.huge
    for _, frame in pairs(display_frames) do
      available_width = math.min(available_width,
        frame.width - right_inset - left_offset - indicator_width - front_app_width - safety_gap)
    end
    available_width = positive_number(available_width)
  else
    available_width = positive_number(right - left - indicator_width - front_app_width - safety_gap)
  end
  local content_width = positive_number(space_labels.content_width(labels, active_space_count))
  if not available_width then return nil end
  if not content_width then return available_width end

  return math.min(available_width, content_width)
end

local function effective_overlay_width()
  return configured_overlay_width
    or automatic_overlay_width()
    or current_overlay_width
    or positive_number(settings.spaces_fallback_width)
end

local function refresh_overlay_geometry()
  if indicator_measurement_phase == 0 then
    local item, display_index = measurement_indicator()
    if not item then return end
    indicator_measurement_display = display_index
    item:set({ label = { width = 0 } })
    indicator_measurement_phase = 1
    sbar.delay(0.05, refresh_overlay_geometry)
    return
  end
  if indicator_measurement_phase == 1 then
    local display_index = indicator_measurement_display
    local item = display_index and indicators[display_index]
    if not item then
      indicator_measurement_display = nil
      indicator_measurement_phase = 0
      return
    end
    indicator_collapsed_width = geometry_width(item)
    item:set({ label = { width = "dynamic" } })
    indicator_measurement_phase = 2
    sbar.delay(0.05, refresh_overlay_geometry)
    return
  end
  if indicator_measurement_phase == 2 then
    local display_index = indicator_measurement_display
    local item = display_index and indicators[display_index]
    if not item then
      indicator_measurement_display = nil
      indicator_measurement_phase = 0
      return
    end
    local measured = geometry_width(item)
    local collapsed = indicator_collapsed_width or 0
    if measured and measured > collapsed then
      expanded_indicator_width = measured
    else
      expanded_indicator_width = collapsed + indicator_label_delta
    end
    if not indicator_hovered[display_index] then
      item:set({ label = { width = 0 } })
    end
    indicator_probe = item
    indicator_probe_display = display_index
    indicator_measurement_phase = 3
    sbar.delay(0.05, refresh_overlay_geometry)
    return
  end

  local next_width = effective_overlay_width()
  if math.abs(next_width - current_overlay_width) <= 0.5 then
    sync_snapshot()
    return
  end

  current_overlay_width = next_width
  overlay:set({ width = next_width })
  if last_rect and last_rect.size then last_rect.size[1] = next_width end
  sbar.delay(0.05, sync_snapshot)
end

schedule_geometry_sync = function(delay)
  geometry_sync_generation = geometry_sync_generation + 1
  local generation = geometry_sync_generation
  sbar.delay(delay or 0.05, function()
    if generation == geometry_sync_generation then refresh_overlay_geometry() end
  end)
end

local function set_front_app_visible(show)
  if front_app_controller and front_app_controller.set_visible then
    front_app_controller.set_visible(show)
  elseif front_app_item then
    front_app_item:set({ drawing = show })
  end
end

local swap_observer = sbar.add("item", "spaces.swap_observer", {
  drawing = false,
  updates = true,
})

swap_observer:subscribe("swap_menus_and_spaces", function(_)
  visible = not visible
  for _, item in pairs(indicators) do
    item:set({ icon = { string = visible and icons.switch.on or icons.switch.off } })
  end

  sync_snapshot(true)
  overlay:set({ drawing = visible })

  if visible then
    if menu_controller then menu_controller.hide() end
    set_front_app_visible(true)
  else
    if menu_controller then menu_controller.show() end
    set_front_app_visible(false)
  end
end)

local geometry_observer = sbar.add("item", "spaces.geometry_observer", {
  drawing = false,
  updates = true,
})

geometry_observer:subscribe("display_change", function(_)
  refresh_displays()
  schedule_geometry_sync(0.1)
end)

geometry_observer:subscribe({
  "front_app_switched",
  "media_change",
  "volume_change",
  "wifi_change",
  "power_source_change",
  "network_update",
  "system_woke",
}, function(_)
  schedule_geometry_sync(0.1)
end)

local function refresh_space_count()
  sbar.exec(
    yabai_command .. " -m query --spaces"
      .. " | /opt/homebrew/bin/jq -r 'length, (map(select(.\"has-focus\" == true))[0].index // 1), (map([.index, (.display // 1)] | @tsv) | join(\"\\n\"))'",
    function(output)
      local lines = {}
      for line in (output or ""):gmatch("[^\r\n]+") do
        lines[#lines + 1] = line
      end
      local count = tonumber(lines[1])
      local selected = tonumber(lines[2])
      if not count or count < 1 then return end

      local displays = {}
      for line_index = 3, #lines do
        local index_text, display_text = lines[line_index]:match("^(%d+)%s+(%d+)$")
        local index = tonumber(index_text)
        local display = tonumber(display_text)
        if index and display then displays[index] = display end
      end
      space_displays = displays

      active_space_count = math.min(count, space_capacity)
      if selected and selected >= 1 and selected <= active_space_count then
        selected_space = selected
      elseif selected_space > active_space_count then
        selected_space = active_space_count
      end

      for index = active_space_count + 1, space_capacity do
        labels[index] = {}
      end
      refresh_displays()
      sync_snapshot(true)
      refresh_space_labels()
      schedule_geometry_sync()
    end
  )
end

local space_count_observer = sbar.add("item", "spaces.count_observer", {
  drawing = false,
  updates = true,
})
space_count_observer:subscribe(space_count_event, refresh_space_count)

local signal_prefix = "com.vision3.sketchybar.spaces"
sbar.exec(
  yabai_command .. " -m signal --remove " .. signal_prefix .. ".created 2>/dev/null; "
    .. yabai_command .. " -m signal --remove " .. signal_prefix .. ".destroyed 2>/dev/null; "
    .. yabai_command .. " -m signal --remove " .. signal_prefix .. ".focused 2>/dev/null; "
    .. yabai_command .. " -m signal --remove " .. signal_prefix .. ".window_destroyed 2>/dev/null; "
    .. yabai_command .. " -m signal --add label=" .. signal_prefix .. ".created"
    .. " event=space_created action='/opt/homebrew/bin/sketchybar --trigger " .. space_count_event .. "'; "
    .. yabai_command .. " -m signal --add label=" .. signal_prefix .. ".destroyed"
    .. " event=space_destroyed action='/opt/homebrew/bin/sketchybar --trigger " .. space_count_event .. "'; "
    .. yabai_command .. " -m signal --add label=" .. signal_prefix .. ".focused"
    .. " event=window_focused action='/opt/homebrew/bin/sketchybar --trigger " .. window_focus_event .. "'; "
    .. yabai_command .. " -m signal --add label=" .. signal_prefix .. ".window_destroyed"
    .. " event=window_destroyed action='/opt/homebrew/bin/sketchybar --trigger " .. window_destroyed_event .. "'"
)

local function start(front_app, menus)
  if started then return end
  started = true
  if front_app and front_app.items then
    front_app_controller = front_app
    front_app_item = nil
    if front_app.set_visible then front_app.set_visible(visible) end
  else
    front_app_item = front_app
  end
  menu_controller = menus
  right_boundary = sbar.add("item", "spaces.right_boundary", {
    position = "right",
    width = 1,
    padding_left = 0,
    padding_right = 0,
    icon = { drawing = false },
    label = { drawing = false },
    background = { drawing = false },
  })

  refresh_displays()
  refresh_space_count()
  schedule_geometry_sync(0.2)
  sbar.delay(0.8, refresh_overlay_geometry)
end

return { start = start }
