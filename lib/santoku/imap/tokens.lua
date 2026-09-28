local str = require("santoku.string")
local arr = require("santoku.array")

local function tokenize (pieces)
  local toks = {}
  for i = 1, #pieces do
    local p = pieces[i]
    if p.lit then
      arr.push(toks, { s = p.s, q = true })
    else
      local s = p.s
      local pos = 1
      local n = #s
      while pos <= n do
        local c = str.sub(s, pos, pos)
        if c == " " then
          pos = pos + 1
        elseif c == "(" or c == ")" or c == "[" or c == "]" then
          arr.push(toks, { s = c })
          pos = pos + 1
        elseif c == "\"" then
          local out = {}
          pos = pos + 1
          while pos <= n do
            local ch = str.sub(s, pos, pos)
            if ch == "\\" then
              arr.push(out, str.sub(s, pos + 1, pos + 1))
              pos = pos + 2
            elseif ch == "\"" then
              pos = pos + 1
              break
            else
              arr.push(out, ch)
              pos = pos + 1
            end
          end
          arr.push(toks, { s = arr.concat(out), q = true })
        else
          local e = str.find(s, "[%s%(%)%[%]\"]", pos)
          local stop = (e or (n + 1)) - 1
          arr.push(toks, { s = str.sub(s, pos, stop) })
          pos = stop + 1
        end
      end
    end
  end
  return toks
end

local function is_open (t)
  return t and not t.q and t.s == "("
end

local function is_close (t)
  return t and not t.q and t.s == ")"
end

local function skip_group (toks, i)
  local depth = 0
  while toks[i] do
    local t = toks[i]
    if is_open(t) then
      depth = depth + 1
    elseif is_close(t) then
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
  if not is_open(t) then
    return t.s, i + 1
  end
  local vals = {}
  local depth = 0
  i = i + 1
  while toks[i] do
    local x = toks[i]
    if is_open(x) then
      depth = depth + 1
    elseif is_close(x) then
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

local function read_tree (toks, i)
  local t = toks[i]
  if not t then
    return nil, i
  end
  if not is_open(t) then
    return t.s, i + 1
  end
  local vals = {}
  i = i + 1
  while toks[i] and not is_close(toks[i]) do
    local v
    v, i = read_tree(toks, i)
    vals[#vals + 1] = v
  end
  return vals, i + 1
end

return {
  tokenize = tokenize,
  is_open = is_open,
  is_close = is_close,
  skip_group = skip_group,
  read_value = read_value,
  read_tree = read_tree,
}
