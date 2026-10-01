-- SPDX-License-Identifier: MIT
-- SPDX-FileCopyrightText: 2026 Birch Point SWE
local test = require("santoku.test")
local err = require("santoku.error")
local utc = require("santoku.utc")
local date = require("santoku.imap.date")

local function at (y, mo, d, h, mi, s)
  return utc.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
end

test("internaldate parses utc", function ()
  err.assert(date.internaldate("27-Sep-2026 08:51:00 +0000") == at(2026, 9, 27, 8, 51, 0))
end)

test("internaldate applies the zone", function ()
  err.assert(date.internaldate("27-Sep-2026 08:51:00 -0500") == at(2026, 9, 27, 13, 51, 0))
  err.assert(date.internaldate("27-Sep-2026 08:51:00 +0130") == at(2026, 9, 27, 7, 21, 0))
end)

test("internaldate accepts a space padded day", function ()
  err.assert(date.internaldate(" 7-Sep-2026 00:00:00 +0000") == at(2026, 9, 7, 0, 0, 0))
end)

test("internaldate rejects garbage", function ()
  err.assert(date.internaldate("Sat, 27 Sep 2026 08:51:00 +0000") == nil)
  err.assert(date.internaldate("") == nil)
  err.assert(date.internaldate(nil) == nil)
  err.assert(date.internaldate("27-Xyz-2026 08:51:00 +0000") == nil)
end)

test("rfc2822 parses numeric zones", function ()
  err.assert(date.rfc2822("Sat, 27 Sep 2026 08:51:00 -0400") == at(2026, 9, 27, 12, 51, 0))
  err.assert(date.rfc2822("27 Sep 2026 08:51 +0000") == at(2026, 9, 27, 8, 51, 0))
end)

test("rfc2822 parses named zones and two digit years", function ()
  err.assert(date.rfc2822("Sat, 27 Sep 26 08:51:00 EST") == at(2026, 9, 27, 13, 51, 0))
  err.assert(date.rfc2822("Sat, 27 Sep 2026 08:51:00 GMT") == at(2026, 9, 27, 8, 51, 0))
  err.assert(date.rfc2822("Sat, 27 Sep 2026 08:51:00 XYZ") == at(2026, 9, 27, 8, 51, 0))
end)

test("rfc2822 rejects garbage", function ()
  err.assert(date.rfc2822("nope") == nil)
  err.assert(date.rfc2822(nil) == nil)
end)
