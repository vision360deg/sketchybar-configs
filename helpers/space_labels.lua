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

return M
