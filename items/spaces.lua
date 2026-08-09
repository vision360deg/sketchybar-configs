local colors = require("colors")
local icons = require("icons")
local settings = require("settings")
local space_labels = require("helpers.space_labels")

local overlay_config = {}
local config_dir = os.getenv("CONFIG_DIR") or "."
local config_ok, loaded_config = pcall(dofile, config_dir .. "/helpers/spaces_overlay/config.lua")
if config_ok and type(loaded_config) == "table" then
  overlay_config = loaded_config
end

local space_capacity = 32
local active_space_count
local space_count_event = "spaces_count_changed"
local space_order_event = "spaces_order_changed"
local safety_gap = 12
local service_name = "com.vision3.sketchybar.spaces"
local sync_event = "spaces_overlay_sync"
local labels = {}
local selected_space = 1
local revision = 0
local visible = true
local content_sync_generation = 0
local geometry_sync_generation = 0
local expanded_indicator_width
local indicator_hovered = false
local indicator_measurement_complete = false
local menu_controller
local last_rect
local front_app_item
local right_boundary
local started = false

for index = 1, space_capacity do
  labels[index] = {}
end

sbar.add("event", sync_event)
sbar.add("event", space_count_event)
sbar.add("event", space_order_event)

local function positive_number(value)
  return type(value) == "number" and value > 0 and value or nil
end

local function query_item(item)
  if not item then return nil end
  local ok, result = pcall(function() return item:query() end)
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
    local rect = result.bounding_rects[display]
    if rect.origin and rect.origin[1] > -9000 then return rect end
  end

  for _, rect in pairs(result.bounding_rects) do
    if rect.origin and rect.origin[1] > -9000 then return rect end
  end
end

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
  sbar.trigger(sync_event, {
    REVISION = tostring(revision),
    VISIBLE = visible and "true" or "false",
    X = tostring(rect.origin[1]),
    Y = tostring(rect.origin[2]),
    WIDTH = tostring(rect.size[1]),
    HEIGHT = tostring(rect.size[2]),
    SELECTED = tostring(selected_space),
    LABELS = encoded_labels(),
    REARRANGE_SPACES = overlay_config.rearrange_spaces == true and "true" or "false",
  })
end

local function schedule_sync(delay)
  content_sync_generation = content_sync_generation + 1
  local generation = content_sync_generation
  sbar.delay(delay or 0.05, function()
    if generation == content_sync_generation then sync_snapshot() end
  end)
end

local function refresh_space_labels()
  if not active_space_count then return end

  sbar.exec(
    "/opt/homebrew/bin/yabai -m query --windows"
      .. " | /opt/homebrew/bin/jq -r '.[] | [.space, (.app // \"\")] | @tsv'",
    function(output)
      labels = space_labels.rebuild(output, space_capacity)
      sync_snapshot(true)
      schedule_geometry_sync()
    end
  )
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
    if env.SELECTED == "true" then selected_space = index end
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

  local apps = {}
  for app, _ in pairs(env.INFO.apps or {}) do
    apps[#apps + 1] = app
  end
  table.sort(apps)
  labels[index] = apps
  schedule_sync()
  schedule_geometry_sync()
end)

local space_order_observer = sbar.add("item", "spaces.order_observer", {
  drawing = false,
  updates = true,
})

space_order_observer:subscribe(space_order_event, refresh_space_labels)

local spaces_indicator = sbar.add("item", "spaces.indicator", {
  padding_left = 2,
  padding_right = 0,
  icon = {
    padding_left = 8,
    padding_right = 9,
    color = colors.grey,
    string = icons.switch.on,
  },
  label = {
    width = "dynamic",
    padding_left = 0,
    padding_right = 8,
    string = "Spaces",
    color = colors.with_alpha(colors.bg1, 0.0),
  },
  background = {
    color = colors.with_alpha(colors.grey, 0.0),
    border_color = colors.with_alpha(colors.bg1, 0.0),
  },
})

local function automatic_overlay_width()
  local left = geometry_position(overlay)
  local right = geometry_position(right_boundary)
  local indicator_width = expanded_indicator_width or geometry_width(spaces_indicator) or 0
  local front_app_width = geometry_width(front_app_item) or 0
  if not left or not right or right <= left then return nil end

  local available_width = positive_number(right - left - indicator_width - front_app_width - safety_gap)
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

local function finish_indicator_measurement()
  if indicator_measurement_complete or not expanded_indicator_width then return false end

  indicator_measurement_complete = true
  if indicator_hovered then return false end

  spaces_indicator:set({ label = { width = 0 } })
  return true
end

local function refresh_overlay_geometry()
  expanded_indicator_width = expanded_indicator_width or geometry_width(spaces_indicator)
  local next_width = effective_overlay_width()
  local indicator_collapsed = finish_indicator_measurement()
  if math.abs(next_width - current_overlay_width) <= 0.5 then
    if indicator_collapsed then
      sbar.delay(0.05, sync_snapshot)
    else
      sync_snapshot()
    end
    return
  end

  current_overlay_width = next_width
  overlay:set({ width = next_width })
  if last_rect and last_rect.size then last_rect.size[1] = next_width end
  sbar.delay(0.05, sync_snapshot)
end

local function schedule_geometry_sync(delay)
  geometry_sync_generation = geometry_sync_generation + 1
  local generation = geometry_sync_generation
  sbar.delay(delay or 0.05, function()
    if generation == geometry_sync_generation then refresh_overlay_geometry() end
  end)
end

spaces_indicator:subscribe("swap_menus_and_spaces", function(_)
  visible = not visible
  spaces_indicator:set({
    icon = visible and icons.switch.on or icons.switch.off,
  })

  sync_snapshot(true)
  overlay:set({ drawing = visible })

  if visible then
    if menu_controller then menu_controller.hide() end
    if front_app_item then front_app_item:set({ drawing = true }) end
  else
    if menu_controller then menu_controller.show() end
    if front_app_item then front_app_item:set({ drawing = false }) end
  end
end)


spaces_indicator:subscribe("mouse.entered", function(_)
  indicator_hovered = true
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 1.0 },
        border_color = { alpha = 1.0 },
      },
      icon = { color = colors.bg1 },
      label = { width = "dynamic", color = { alpha = 1.0 } },
    })
  end)
end)

spaces_indicator:subscribe("mouse.exited", function(_)
  indicator_hovered = false
  sbar.animate("tanh", 30, function()
    spaces_indicator:set({
      background = {
        color = { alpha = 0.0 },
        border_color = { alpha = 0.0 },
      },
      icon = { color = colors.grey },
      label = { width = 0, color = { alpha = 0.0 } },
    })
  end)
end)

spaces_indicator:subscribe("mouse.clicked", function(_)
  sbar.trigger("swap_menus_and_spaces")
end)

local geometry_observer = sbar.add("item", "spaces.geometry_observer", {
  drawing = false,
  updates = true,
})

geometry_observer:subscribe({
  "display_change",
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
    "/opt/homebrew/bin/yabai -m query --spaces"
      .. " | /opt/homebrew/bin/jq -r 'length, (map(select(.\"has-focus\" == true))[0].index // 1)'",
    function(output)
      local count_text, selected_text = output:match("(%d+)%s+(%d+)")
      local count = tonumber(count_text)
      local selected = tonumber(selected_text)
      if not count or count < 1 then return end

      active_space_count = math.min(count, space_capacity)
      if selected and selected >= 1 and selected <= active_space_count then
        selected_space = selected
      elseif selected_space > active_space_count then
        selected_space = active_space_count
      end

      for index = active_space_count + 1, space_capacity do
        labels[index] = {}
      end
      sync_snapshot(true)
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
  "/opt/homebrew/bin/yabai -m signal --remove " .. signal_prefix .. ".created 2>/dev/null; "
    .. "/opt/homebrew/bin/yabai -m signal --remove " .. signal_prefix .. ".destroyed 2>/dev/null; "
    .. "/opt/homebrew/bin/yabai -m signal --add label=" .. signal_prefix .. ".created"
    .. " event=space_created action='/opt/homebrew/bin/sketchybar --trigger " .. space_count_event .. "'; "
    .. "/opt/homebrew/bin/yabai -m signal --add label=" .. signal_prefix .. ".destroyed"
    .. " event=space_destroyed action='/opt/homebrew/bin/sketchybar --trigger " .. space_count_event .. "'"
)

local function start(front_app, menus)
  if started then return end
  started = true
  front_app_item = front_app
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

  refresh_space_count()
  schedule_geometry_sync(0.2)
  sbar.delay(0.8, refresh_overlay_geometry)
end

return { start = start }
