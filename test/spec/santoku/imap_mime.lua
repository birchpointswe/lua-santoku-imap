local test = require("santoku.test")
local err = require("santoku.error")
local str = require("santoku.string")
local mime = require("santoku.imap.mime")

test("build reply", function ()
  local m = mime.build({
    from = "me@x.y",
    to = "a@b.c",
    subject = "Re: Hi",
    in_reply_to = "orig@b.c",
    references = { "root@b.c", "orig@b.c" },
    paragraphs = { "First para.", "Second para." },
  })
  err.assert(str.find(m, "From: me@x.y\r\n", 1, true))
  err.assert(str.find(m, "To: a@b.c\r\n", 1, true))
  err.assert(str.find(m, "Subject: Re: Hi\r\n", 1, true))
  err.assert(str.find(m, "In-Reply-To: <orig@b.c>\r\n", 1, true))
  err.assert(str.find(m, "References: <root@b.c> <orig@b.c>\r\n", 1, true))
  err.assert(str.find(m, "\r\n\r\nFirst para.\r\n\r\nSecond para.\r\n", 1, true))
  err.assert(str.find(m, "Content-Type: text/plain; charset=utf-8\r\n", 1, true))
end)

test("message id header", function ()
  local m = mime.build({
    message_id = "abc123.1@mail.example.com",
    paragraphs = { "x" },
  })
  err.assert(str.find(m,
    "Message-ID: <abc123.1@mail.example.com>\r\n", 1, true))
  local m2 = mime.build({ paragraphs = { "x" } })
  err.assert(not str.find(m2, "Message-ID", 1, true))
end)

test("non ascii subject encodes", function ()
  local m = mime.build({ subject = "héj", paragraphs = { "x" } })
  err.assert(str.find(m, "Subject: =?UTF-8?B?", 1, true))
  err.assert(not str.find(m, "héj", 1, true))
end)

test("ascii subject stays plain", function ()
  err.assert(mime.encode_word("plain") == "plain")
end)

test("paragraph newlines normalized to crlf", function ()
  local m = mime.build({ paragraphs = { "a\nb" } })
  err.assert(str.find(m, "a\r\nb", 1, true))
  err.assert(not str.find(m, "[^\r]\na", 1, false))
end)

test("omitted headers absent", function ()
  local m = mime.build({ paragraphs = { "x" } })
  err.assert(not str.find(m, "In%-Reply%-To"))
  err.assert(not str.find(m, "References:", 1, true))
  err.assert(not str.find(m, "To:", 1, true))
end)

test("ends with crlf", function ()
  local m = mime.build({ paragraphs = { "x" } })
  err.assert(str.sub(m, -2) == "\r\n")
end)
