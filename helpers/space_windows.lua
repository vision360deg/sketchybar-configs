local M = {}

local function empty_records(capacity)
  local records = {}
  for index = 1, capacity do records[index] = {} end
  return records
end

function M.rebuild(output, capacity, previous_records)
  local records = empty_records(capacity)
  for line in (output or ""):gmatch("[^\r\n]+") do
    local space_text, id_text, app, minimized_text, hidden_text, focused_text, ax_reference_text =
      line:match("^(%d+)\t(%d+)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)$")
    if not space_text then
      space_text, id_text, app, minimized_text, hidden_text, focused_text =
        line:match("^(%d+)\t(%d+)\t(.-)\t(.-)\t(.-)\t(.-)$")
    end
    if not space_text then
      space_text, id_text, app, minimized_text, hidden_text, focused_text =
        line:match("^(%d+)\t(%d+)\t(.-)\t(.-)\t(.-)$")
    end
    if not space_text then
      space_text, id_text, app = line:match("^(%d+)\t(%d+)\t(.*)$")
    end
    local space = tonumber(space_text)
    local id = tonumber(id_text)
    local minimized = minimized_text == "true"
    local hidden = hidden_text == "true"
    local has_ax_reference = ax_reference_text == nil or ax_reference_text == "true"
    if space and id and space >= 1 and space <= capacity and id > 0
        and not minimized and not hidden and has_ax_reference then
      records[space][#records[space] + 1] = { id = id, app = app or "" }
      records[space][#records[space]].focused = focused_text == "true"
    end
  end

  for space = 1, capacity do
    local previous_positions = {}
    for position, record in ipairs(previous_records and previous_records[space] or {}) do
      previous_positions[record.id] = position
    end

    table.sort(records[space], function(first, second)
      local first_app = first.app == "" and "\255" or first.app
      local second_app = second.app == "" and "\255" or second.app
      if first_app ~= second_app then return first_app < second_app end

      local first_position = previous_positions[first.id]
      local second_position = previous_positions[second.id]
      if first_position and second_position and first_position ~= second_position then
        return first_position < second_position
      end
      if first_position ~= nil then return true end
      if second_position ~= nil then return false end
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
