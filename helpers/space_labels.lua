local M = {}

function M.rebuild(output, app_icons, capacity)
  local rebuilt = {}
  local seen = {}
  for index = 1, capacity do rebuilt[index] = "" end

  for line in (output or ""):gmatch("[^\r\n]+") do
    local index_text, app = line:match("^(%d+)\t(.*)$")
    local index = tonumber(index_text)
    if index and index >= 1 and index <= capacity and app ~= "" then
      seen[index] = seen[index] or {}
      if not seen[index][app] then
        rebuilt[index] = rebuilt[index] .. (app_icons[app] or app_icons.Default)
        seen[index][app] = true
      end
    end
  end

  return rebuilt
end

return M
