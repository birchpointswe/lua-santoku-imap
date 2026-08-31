local arr = require("santoku.array")

local function forest (msgs)
  local bymsgid = {}
  for i = 1, #msgs do
    local m = msgs[i]
    if m.msgid and not bymsgid[m.msgid] then
      bymsgid[m.msgid] = m
    end
  end
  local parent = {}
  for i = 1, #msgs do
    local m = msgs[i]
    local refs = m.refs or {}
    for j = #refs, 1, -1 do
      local p = bymsgid[refs[j]]
      if p and p ~= m then
        parent[m] = p
        break
      end
    end
  end
  for i = 1, #msgs do
    local m = msgs[i]
    local seen = { [m] = true }
    local p = parent[m]
    while p do
      if seen[p] then
        parent[m] = nil
        break
      end
      seen[p] = true
      p = parent[p]
    end
  end
  local groots = {}
  for i = 1, #msgs do
    local m = msgs[i]
    if not parent[m] and m.thrid then
      local g = groots[m.thrid]
      if not g then
        groots[m.thrid] = m
      elseif (m.uid or 0) < (g.uid or 0) then
        parent[g] = m
        groots[m.thrid] = m
      else
        parent[m] = g
      end
    end
  end
  local nodes = {}
  for i = 1, #msgs do
    nodes[msgs[i]] = { msg = msgs[i], children = {} }
  end
  local roots = {}
  for i = 1, #msgs do
    local m = msgs[i]
    if parent[m] then
      arr.push(nodes[parent[m]].children, nodes[m])
    else
      arr.push(roots, nodes[m])
    end
  end
  local function sortrec (list)
    table.sort(list, function (a, b)
      return (a.msg.uid or 0) < (b.msg.uid or 0)
    end)
    for i = 1, #list do
      sortrec(list[i].children)
    end
  end
  sortrec(roots)
  return roots
end

return {
  forest = forest,
}
