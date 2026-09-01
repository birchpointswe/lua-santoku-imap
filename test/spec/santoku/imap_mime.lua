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

test("extract plain 7bit", function ()
  local t = mime.extract_text("text/plain; charset=utf-8", nil,
    "Hello there.\r\n\r\nSecond para.\r\n")
  err.assert(str.find(t, "Hello there.", 1, true))
  err.assert(str.find(t, "Second para.", 1, true))
end)

test("extract quoted printable", function ()
  local t = mime.extract_text("text/plain", "quoted-printable",
    "caf=C3=A9 and a soft=\r\n break")
  err.assert(str.find(t, "café and a soft break", 1, true))
end)

test("extract base64", function ()
  local t = mime.extract_text("text/plain", "base64",
    str.to_base64("body via base64"))
  err.assert(t == "body via base64")
end)

test("multipart alternative prefers plain", function ()
  local raw = "--bnd\r\nContent-Type: text/html\r\n\r\n"
    .. "<p>html version</p>\r\n"
    .. "--bnd\r\nContent-Type: text/plain\r\n\r\n"
    .. "plain version\r\n"
    .. "--bnd--\r\n"
  local t = mime.extract_text(
    "multipart/alternative; boundary=\"bnd\"", nil, raw)
  err.assert(str.find(t, "plain version", 1, true))
  err.assert(not str.find(t, "html version", 1, true))
end)

test("html only gets stripped", function ()
  local raw = "--b2\r\nContent-Type: text/html\r\n"
    .. "Content-Transfer-Encoding: quoted-printable\r\n\r\n"
    .. "<div>Hi<br>there &amp; friends</div>\r\n"
    .. "--b2--\r\n"
  local t = mime.extract_text("multipart/alternative; boundary=b2", nil, raw)
  err.assert(str.find(t, "Hi", 1, true))
  err.assert(str.find(t, "there & friends", 1, true))
  err.assert(not str.find(t, "<div>", 1, true))
end)

test("nested multipart finds plain", function ()
  local inner = "--in\r\nContent-Type: text/plain\r\n\r\n"
    .. "deep plain\r\n--in--\r\n"
  local raw = "--out\r\n"
    .. "Content-Type: multipart/alternative; boundary=\"in\"\r\n\r\n"
    .. inner
    .. "--out--\r\n"
  local t = mime.extract_text("multipart/mixed; boundary=out", nil, raw)
  err.assert(str.find(t, "deep plain", 1, true))
end)

test("non text part yields nil", function ()
  err.assert(mime.extract_text("image/jpeg", "base64", "xxxx") == nil)
  err.assert(mime.extract_text("text/plain", nil, "") == nil)
end)

test("paragraphs split and collapse", function ()
  local p = mime.paragraphs("one line\nwrapped here\n\n\nsecond block\n")
  err.assert(#p == 2)
  err.assert(p[1] == "one line wrapped here")
  err.assert(p[2] == "second block")
end)

test("paragraphs cap length and count", function ()
  local long = string.rep("a", 3000)
  local p = mime.paragraphs(long, { max_len = 100 })
  err.assert(#p == 2)
  err.assert(#p[1] == 100)
  err.assert(p[2] == "[truncated]")
  local many = {}
  for i = 1, 10 do
    many[i] = "p" .. i
  end
  local p2 = mime.paragraphs(table.concat(many, "\n\n"), { max_count = 3 })
  err.assert(#p2 == 4)
  err.assert(p2[4] == "[truncated]")
end)
