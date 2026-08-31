local test = require("santoku.test")
local err = require("santoku.error")
local str = require("santoku.string")
local headers = require("santoku.imap.headers")

test("parse unfolds and lowercases", function ()
  local h = headers.parse("Subject: one\r\n two\r\nFrom: a@b\r\n\r\n")
  err.assert(h.subject == "one two")
  err.assert(h.from == "a@b")
end)

test("first occurrence wins", function ()
  local h = headers.parse("Received: x\r\nReceived: y\r\n")
  err.assert(h.received == "x")
end)

test("rfc2047 base64", function ()
  local s = headers.decode("=?UTF-8?B?" .. str.to_base64("héllo") .. "?=")
  err.assert(s == "héllo")
end)

test("rfc2047 q encoding", function ()
  err.assert(headers.decode("=?utf-8?Q?a_b=21?=") == "a b!")
end)

test("adjacent encoded words join", function ()
  local a = "=?UTF-8?B?" .. str.to_base64("ab") .. "?="
  local b = "=?UTF-8?B?" .. str.to_base64("cd") .. "?="
  err.assert(headers.decode(a .. " " .. b) == "abcd")
end)

test("bad base64 passes through", function ()
  local s = headers.decode("=?UTF-8?B?!!notb64!!?=")
  err.assert(type(s) == "string")
end)

test("ids extracts message ids", function ()
  local out = headers.ids("<a@x> <b@y>\r\n <c@z>")
  err.assert(#out == 3)
  err.assert(out[1] == "a@x" and out[2] == "b@y" and out[3] == "c@z")
end)

test("ids empty on nil", function ()
  err.assert(#headers.ids(nil) == 0)
end)

test("address with display name", function ()
  local addr, name = headers.address("\"Ann B\" <a@b.c>")
  err.assert(addr == "a@b.c")
  err.assert(name == "Ann B")
end)

test("address bare", function ()
  local addr, name = headers.address("a@b.c")
  err.assert(addr == "a@b.c")
  err.assert(name == nil)
end)

test("address encoded name", function ()
  local addr, name = headers.address(
    "=?UTF-8?B?" .. str.to_base64("Åsa") .. "?= <asa@b.c>")
  err.assert(addr == "asa@b.c")
  err.assert(name == "Åsa")
end)
