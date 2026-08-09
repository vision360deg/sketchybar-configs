local M = {}

local function empty_records(capacity)
  local records = {}
  for index = 1, capacity do records[index] = {} end
  return records
end

function M.rebuild(output, capacity)
  local records = empty_records(capacity)
  for line in (output or ""):gmatch("[^\r\n]+") do
    local space_text, id_text, app, minimized_text, hidden_text, focused_text =
      line:match("^(%d+)\t(%d+)\t(.-)\t(.-)\t(.-)\t(.-)$")
    if not space_text then
      space_text, id_text, app, minimized_text, hidden_text =
        line:match("^(%d+)\t(%d+)\t(.-)\t(.-)\t(.-)$")
    end
    if not space_text then
      space_text, id_text, app = line:match("^(%d+)\t(%d+)\t(.*)$")
    end
    local space = tonumber(space_text)
    local id = tonumber(id_text)
    local minimized = minimized_text == "true"
    local hidden = hidden_text == "true"
    if space and id and space >= 1 and space <= capacity and id > 0
        and not minimized and not hidden then
      records[space][#records[space] + 1] = { id = id, app = app or "" }
      records[space][#records[space]].focused = focused_text == "true"
    end
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
