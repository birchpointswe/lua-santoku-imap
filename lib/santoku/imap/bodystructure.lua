local str = require("santoku.string")

local function lower (s)
  if type(s) ~= "string" then
    return nil
  end
  return str.lower(s)
end

local function skip_group (toks, i)
  local depth = 0
  while toks[i] do
    local t = toks[i]
    if not t.q and t.s == "(" then
      depth = depth + 1
    elseif not t.q and t.s == ")" then
      if depth == 0 then
        return i + 1
      end
      depth = depth - 1
    end
    i = i + 1
  end
  return i
end

local function read_value (toks, i)
  local t = toks[i]
  if not t then
    return nil, i
  end
  if t.q or t.s ~= "(" then
    return t.s, i + 1
  end
  local vals = {}
  local depth = 0
  i = i + 1
  while toks[i] do
    local x = toks[i]
    if not x.q and x.s == "(" then
      depth = depth + 1
    elseif not x.q and x.s == ")" then
      if depth == 0 then
        return vals, i + 1
      end
      depth = depth - 1
    elseif depth == 0 then
      vals[#vals + 1] = x.s
    end
    i = i + 1
  end
  return vals, i
end

local function skip_value (toks, i)
  local _
  _, i = read_value(toks, i)
  return i
end

local function params_map (v)
  local out = {}
  if type(v) ~= "table" then
    return out
  end
  for i = 1, #v - 1, 2 do
    out[lower(v[i]) or v[i]] = v[i + 1]
  end
  return out
end

local function parse (toks, i)
  i = i + 1
  local node
  if toks[i] and not toks[i].q and toks[i].s == "(" then
    local parts = {}
    while toks[i] and not toks[i].q and toks[i].s == "(" do
      local child
      child, i = parse(toks, i)
      parts[#parts + 1] = child
    end
    node = {
      type = "multipart",
      subtype = toks[i] and lower(toks[i].s) or nil,
      parts = parts,
    }
  else
    local mtype = toks[i] and toks[i].s
    local msub = toks[i + 1] and toks[i + 1].s
    i = i + 2
    local params, enc, size
    params, i = read_value(toks, i)
    i = skip_value(toks, i)
    i = skip_value(toks, i)
    enc, i = read_value(toks, i)
    size, i = read_value(toks, i)
    node = {
      type = lower(mtype),
      subtype = lower(msub),
      params = params_map(params),
      encoding = lower(enc),
      size = tonumber(size),
    }
  end
  return node, skip_group(toks, i)
end

local function find (node, prefix, subtype)
  if not node then
    return nil
  end
  if node.type == "multipart" then
    for j = 1, #node.parts do
      local p = prefix and (prefix .. "." .. j) or tostring(j)
      local hit = find(node.parts[j], p, subtype)
      if hit then
        return hit
      end
    end
    return nil
  end
  if node.type == "text" and node.subtype == subtype then
    return {
      part = prefix or "1",
      subtype = node.subtype,
      encoding = node.encoding,
      charset = node.params and node.params.charset,
      size = node.size,
    }
  end
  return nil
end

local function text_part (node)
  return find(node, nil, "plain") or find(node, nil, "html")
end

return {
  parse = parse,
  text_part = text_part,
}
