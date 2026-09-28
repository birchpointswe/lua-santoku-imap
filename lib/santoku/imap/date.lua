local str = require("santoku.string")
local utc = require("santoku.utc")

local MONTHS = {
  jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6,
  jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12,
}

local ZONES = {
  ut = 0, gmt = 0, z = 0,
  est = -5, edt = -4, cst = -6, cdt = -5,
  mst = -7, mdt = -6, pst = -8, pdt = -7,
}

local function month (s)
  return MONTHS[str.lower(str.sub(s or "", 1, 3))]
end

local function zone_offset (zs, zh, zm)
  local sign = zs == "-" and -1 or 1
  return sign * (tonumber(zh) * 3600 + tonumber(zm) * 60)
end

local function epoch (y, mo, d, h, mi, sec)
  return utc.time({
    year = y, month = mo, day = d, hour = h, min = mi, sec = sec,
  })
end

local function internaldate (s)
  if type(s) ~= "string" then
    return nil
  end
  local d, mon, y, h, mi, sec, zs, zh, zm = str.match(s,
    "^%s*(%d%d?)%-(%a%a%a)%-(%d%d%d%d) (%d%d):(%d%d):(%d%d) ([+%-])(%d%d)(%d%d)%s*$")
  if not d then
    return nil
  end
  local mo = month(mon)
  if not mo then
    return nil
  end
  return epoch(tonumber(y), mo, tonumber(d), tonumber(h), tonumber(mi), tonumber(sec))
    - zone_offset(zs, zh, zm)
end

local function rfc2822 (s)
  if type(s) ~= "string" then
    return nil
  end
  local d, mon, y, h, mi = str.match(s, "(%d+)%s+(%a+)%s+(%d+)%s+(%d+):(%d+)")
  if not d then
    return nil
  end
  local mo = month(mon)
  if not mo then
    return nil
  end
  y = tonumber(y)
  if y < 100 then
    y = y + (y < 70 and 2000 or 1900)
  end
  local sec = tonumber(str.match(s, "%d+:%d+:(%d+)")) or 0
  local t = epoch(y, mo, tonumber(d), tonumber(h), tonumber(mi), sec)
  local zs, zh, zm = str.match(s, "([+%-])(%d%d)(%d%d)")
  if zs then
    return t - zone_offset(zs, zh, zm)
  end
  local name = str.match(s, "%d%d:%d%d[:%d]*%s+(%a+)")
  local zn = name and ZONES[str.lower(name)]
  if zn then
    return t - zn * 3600
  end
  return t
end

return {
  internaldate = internaldate,
  rfc2822 = rfc2822,
}
