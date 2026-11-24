local M = {}

local function empty_records(capacity)
  local records = {}
  for index = 1, capacity do records[index] = {} end
  return records
end

-- windows: records parsed by helpers/yabai_state.lua.
-- filters.visible_spaces: set of space indices currently shown on a display.
-- filters.suppressed_ids: set of window ids yabai just reported as destroyed.
--
-- yabai only holds Accessibility references for windows on spaces it has
-- visited since it started; windows elsewhere are reported without one but are
-- real. On a visible space yabai references every window it can manage, so an
-- unreferenced window there is one the window server still lists while it closes.
function M.rebuild(windows, capacity, previous_records, filters)
  local visible_spaces = filters and filters.visible_spaces or {}
  local suppressed_ids = filters and filters.suppressed_ids or {}
  local records = empty_records(capacity)
  for _, window in ipairs(windows or {}) do
    local space = window.space
    local id = window.id
    if space and id and space >= 1 and space <= capacity and id > 0
        and not window.minimized and not window.hidden
        and not suppressed_ids[id]
        and (window.ax_reference or not visible_spaces[space]) then
      records[space][#records[space] + 1] = {
        id = id,
        app = window.app or "",
        display = window.display,
        focused = window.focused == true,
      }
    end
  end

  for space = 1, capacity do
    local previous_positions = {}
    for position, record in ipairs(previous_records and previous_records[space] or {}) do
      previous_positions[record.id] = position
    end

    -- Group by app (unnamed last), keep the previous carousel order, then append
    -- new windows by id. This must stay a strict weak order: table.sort raises
    -- "invalid order function for sorting" otherwise, which drops the refresh.
    table.sort(records[space], function(first, second)
      local first_app = first.app == "" and "\255" or first.app
      local second_app = second.app == "" and "\255" or second.app
      if first_app ~= second_app then return first_app < second_app end

      local first_position = previous_positions[first.id] or math.huge
      local second_position = previous_positions[second.id] or math.huge
      if first_position ~= second_position then
        return first_position < second_position
      end
      return first.id < second.id
    end)
  end

  return records
end

function M.foreground_ids(records, capacity, previous)
  local foreground = {}
  for space = 1, capacity do
    local valid_ids = {}
    local focused_id
    for _, record in ipairs(records[space] or {}) do
      valid_ids[record.id] = true
      if record.focused then focused_id = record.id end
    end

    local previous_id = previous and previous[space] or nil
    if focused_id then
      foreground[space] = focused_id
    elseif previous_id and valid_ids[previous_id] then
      foreground[space] = previous_id
    end
  end
  return foreground
end

function M.apps(records, capacity)
  local labels = empty_records(capacity)
  for space = 1, capacity do
    local seen = {}
    for _, record in ipairs(records[space] or {}) do
      if record.app ~= "" and not seen[record.app] then
        labels[space][#labels[space] + 1] = record.app
        seen[record.app] = true
      end
    end
    table.sort(labels[space])
  end
  return labels
end

function M.serialize_ids(records, capacity)
  local groups = {}
  for space = 1, capacity do
    local ids = {}
    for _, record in ipairs(records[space] or {}) do
      ids[#ids + 1] = tostring(record.id)
    end
    groups[space] = table.concat(ids, ":")
  end
  return table.concat(groups, ",")
end

function M.serialize_foreground_ids(foreground, capacity)
  local groups = {}
  for space = 1, capacity do
    groups[space] = tostring(foreground[space] or "")
  end
  return table.concat(groups, ",")
end

return M
