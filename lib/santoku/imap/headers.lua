local str = require("santoku.string")
local arr = require("santoku.array")

local function decode_qp (s)
  s = str.gsub(s, "_", " ")
  return (str.gsub(s, "=(%x%x)", function (h)
    return str.char(tonumber(h, 16))
  end))
end

local function decode (s)
  if not s then return nil end
  s = str.gsub(s, "(%?=)[ \t]+(=%?)", "%1%2")
  return (str.gsub(s, "=%?([^%?]+)%?([bBqQ])%?([^%?]*)%?=", function (_, enc, data)
    if enc == "b" or enc == "B" then
      local ok, d = pcall(str.from_base64, data)
      if ok and d then return d end
      return data
    end
    return decode_qp(data)
  end))
end

local function parse (raw)
  raw = str.gsub(raw, "\r\n", "\n")
  raw = str.gsub(raw, "\n[ \t]+", " ")
  local out = {}
  for line in str.gmatch(raw, "[^\n]+") do
    local k, v = str.match(line, "^([%w%-]+):%s*(.-)%s*$")
    if k and not out[str.lower(k)] then
      out[str.lower(k)] = v
    end
  end
  return out
end

local function ids (s)
  local out = {}
  if s then
    for id in str.gmatch(s, "<([^<>%s]+)>") do
      arr.push(out, id)
    end
  end
  return out
end

local function address (s)
  if not s then return nil, nil end
  s = decode(s)
  local addr = str.match(s, "<([^<>%s]+)>")
  if addr then
    local name = str.match(s, "^(.-)%s*<")
    name = name and str.gsub(name, "\"", "")
    name = name and str.match(name, "^%s*(.-)%s*$")
    if name == "" then name = nil end
    return addr, name
  end
  addr = str.match(s, "([^%s,<>]+@[^%s,<>]+)")
  return addr, nil
end

return {
  parse = parse,
  decode = decode,
  ids = ids,
  address = address,
}
