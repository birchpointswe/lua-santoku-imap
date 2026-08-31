local test = require("santoku.test")

local err = require("santoku.error")
local assert = err.assert

local validate = require("santoku.validate")
local eq = validate.isequal

local imap = require("santoku.imap")
local headers = require("santoku.imap.headers")
local thread = require("santoku.imap.thread")
local mime = require("santoku.imap.mime")

local hello =
  "Subject: Hello\r\n" ..
  "Message-Id: <root@example.com>\r\n\r\n"

local reply =
  "Subject: Re: Hello\r\n" ..
  "Message-Id: <reply@example.com>\r\n" ..
  "References: <root@example.com>\r\n\r\n"

local replies = {
  ["T1 LOGIN \"me@example.com\" \"app password\"\r\n"] =
    "T1 OK done\r\n",
  ["T2 EXAMINE \"INBOX\"\r\n"] =
    "* 2 EXISTS\r\n* OK [UIDVALIDITY 7] v\r\n"
    .. "* OK [UIDNEXT 3] n\r\nT2 OK done\r\n",
  ["T3 UID SEARCH ALL\r\n"] =
    "* SEARCH 1 2\r\nT3 OK done\r\n",
  ["T4 UID FETCH 1:2 (UID BODY.PEEK[HEADER])\r\n"] =
    "* 1 FETCH (UID 1 BODY[HEADER] {" .. #hello .. "}\r\n" .. hello .. ")\r\n"
    .. "* 2 FETCH (UID 2 BODY[HEADER] {" .. #reply .. "}\r\n" .. reply .. ")\r\n"
    .. "T4 OK done\r\n",
}

local driver = {
  connect = function (opts, done)
    done(true, {
      write = function (d)
        local r = replies[d]
        assert(r ~= nil, d)
        opts.data(r)
      end,
      close = function () end,
    })
    opts.data("* OK ready\r\n")
  end,
}

test("log in, fetch headers, thread the mailbox", function ()
  local roots
  imap(driver).connect({
    host = "imap.example.com", port = 993,
  }, function (ok, client)
    assert(eq(true, ok))
    client.login("me@example.com", "app password", function (lok)
      assert(eq(true, lok))
      client.examine("INBOX", function (eok, info)
        assert(eq(true, eok))
        assert(eq(2, info.exists))
        client.search("ALL", function (sok, uids)
          assert(eq(true, sok))
          assert(eq(2, #uids))
          client.fetch("1:2", "UID BODY.PEEK[HEADER]", function (fok, msgs)
            assert(eq(true, fok))
            local parsed = {}
            for i = 1, #msgs do
              local h = headers.parse(msgs[i].header)
              parsed[i] = {
                uid = msgs[i].uid,
                msgid = headers.ids(h["message-id"])[1],
                refs = headers.ids(h.references),
                subject = headers.decode(h.subject),
              }
            end
            roots = thread.forest(parsed)
          end)
        end)
      end)
    end)
  end)
  assert(eq(1, #roots))
  assert(eq("Hello", roots[1].msg.subject))
  assert(eq("Re: Hello", roots[1].children[1].msg.subject))
end)

test("build a reply draft for APPEND", function ()
  local draft = mime.build({
    from = "me@example.com",
    to = "ann@example.com",
    subject = "Re: Hello",
    in_reply_to = "root@example.com",
    references = { "root@example.com" },
    paragraphs = { "Sounds good.", "See you then." },
  })
  assert(nil ~= string.find(draft,
    "In-Reply-To: <root@example.com>\r\n", 1, true))
  assert(nil ~= string.find(draft,
    "Sounds good.\r\n\r\nSee you then.", 1, true))
end)
