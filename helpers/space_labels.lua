local M = {}
local separator = string.char(31)

function M.rebuild(output, capacity)
  local rebuilt = {}
  local seen = {}
  for index = 1, capacity do
    rebuilt[index] = {}
  end

  for line in (output or ""):gmatch("[^\r\n]+") do
    local index_text, app = line:match("^(%d+)\t(.*)$")
    local index = tonumber(index_text)
    if index and index >= 1 and index <= capacity and app ~= "" then
      seen[index] = seen[index] or {}
      if not seen[index][app] then
        rebuilt[index][#rebuilt[index] + 1] = app
        seen[index][app] = true
      end
    end
  end

  for index = 1, capacity do
    table.sort(rebuilt[index])
  end

  return rebuilt
end

function M.serialize(apps)
  return table.concat(apps or {}, separator)
end

function M.content_width(space_apps, count)
  local total = 0
  for index = 1, count or #(space_apps or {}) do
    local apps = space_apps[index] or {}
    local number_width = 8.4 * #tostring(index)
    local app_count = #apps
    local card_content_width
    if app_count == 0 then
      card_content_width = 20
    else
      card_content_width = 8 + app_count * 16 + math.max(0, app_count - 1) * 4 + 20
    end

    local card_width = math.max(50, 14 + number_width + card_content_width)
    total = total + card_width
    if index > 1 then total = total + 5 end
  end
  return total
end

return M
