-- Offset/limit paging that also respects a byte budget for the encoded reply.
local M = {}

-- names: sorted array of strings; offset: 0-based; limit: max items;
-- render(name) -> table; budget_bytes: stop before the encoded items exceed it
-- (the first item of a page is always returned, however large).
-- Returns items, next (0-based offset of the next page, or nil at the end).
function M.page(names, offset, limit, render, budget_bytes)
  local items, used = {}, 0
  local i = offset + 1
  local last = math.min(#names, offset + limit)
  while i <= last do
    local item = render(names[i])
    local size = #helpers.table_to_json(item) + 1
    if #items > 0 and used + size > budget_bytes then break end
    items[#items + 1] = item
    used = used + size
    i = i + 1
  end
  local nxt = nil
  if i <= #names then nxt = i - 1 end
  return items, nxt
end

return M
