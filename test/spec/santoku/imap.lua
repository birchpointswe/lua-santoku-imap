local test = require("santoku.test")
local err = require("santoku.error")
local imap = require("santoku.imap")

local function fake (script, chunker)
  return {
    connect = function (opts, done)
      local pending = ""
      local step = 1
      local function deliver (s)
        local chunks = chunker and chunker(s) or { s }
        for i = 1, #chunks do
          opts.data(chunks[i])
        end
      end
      local function pump ()
        while script[step] and not script[step].expect do
          local reply = script[step].reply
          step = step + 1
          deliver(reply)
        end
      end
      local conn
      conn = {
        write = function (d)
          pending = pending .. d
          while script[step] and script[step].expect
            and #pending >= #script[step].expect
            and string.sub(pending, 1, #script[step].expect) == script[step].expect do
            pending = string.sub(pending, #script[step].expect + 1)
            local reply = script[step].reply
            step = step + 1
            if reply then deliver(reply) end
            pump()
          end
        end,
        close = function ()
          if opts.closed then opts.closed() end
        end,
      }
      done(true, conn)
      pump()
      return conn
    end,
  }
end

local function bytewise (s)
  local out = {}
  for i = 1, #s do
    out[i] = string.sub(s, i, i)
  end
  return out
end

local GREETING = { reply = "* OK Gimap ready\r\n" }

local function session (script, chunker, fn)
  local got = {}
  imap(fake(script, chunker)).connect({ host = "h", port = 993 }, function (ok, c)
    err.assert(ok, "connect failed")
    got.client = c
    fn(c, got)
  end)
  return got
end

for name, chunker in pairs({ whole = false, bytewise = bytewise }) do

  local ck = chunker or nil

  test("login and examine: " .. name, function ()
    local got = session({
      GREETING,
      { expect = "T1 LOGIN \"u@x\" \"p w\"\r\n", reply = "T1 OK done\r\n" },
      { expect = "T2 EXAMINE \"INBOX\"\r\n",
        reply = "* 3 EXISTS\r\n* OK [UIDVALIDITY 99] a\r\n"
          .. "* OK [UIDNEXT 1000] b\r\nT2 OK done\r\n" },
    }, ck, function (c, got)
      c.login("u@x", "p w", function (ok)
        err.assert(ok, "login failed")
        c.examine("INBOX", function (ok2, info)
          err.assert(ok2, "examine failed")
          got.info = info
        end)
      end)
    end)
    err.assert(got.info, "no examine result")
    err.assert(got.info.exists == 3)
    err.assert(got.info.uidvalidity == "99")
    err.assert(got.info.uidnext == "1000")
  end)

  test("search and fetch with literal: " .. name, function ()
    local hdr = "Subject: Hi there\r\nFrom: Ann <a@b.c>\r\n\r\n"
    local got = session({
      GREETING,
      { expect = "T1 UID SEARCH UID 1:*\r\n",
        reply = "* SEARCH 5 9\r\nT1 OK done\r\n" },
      { expect = "T2 UID FETCH 5,9 (UID X-GM-THRID BODY.PEEK[HEADER.FIELDS "
          .. "(SUBJECT FROM)])\r\n",
        reply = "* 1 FETCH (UID 5 X-GM-THRID 1111222233334444555 "
          .. "BODY[HEADER.FIELDS (SUBJECT FROM)] {" .. #hdr .. "}\r\n"
          .. hdr .. ")\r\n"
          .. "* 2 FETCH (UID 9 X-GM-THRID 1111222233334444555 "
          .. "BODY[HEADER.FIELDS (SUBJECT FROM)] \"Subject: Re\")\r\n"
          .. "T2 OK done\r\n" },
    }, ck, function (c, got)
      c.search("UID 1:*", function (ok, uids)
        err.assert(ok, "search failed")
        got.uids = uids
        c.fetch("5,9", "UID X-GM-THRID BODY.PEEK[HEADER.FIELDS (SUBJECT FROM)]",
          function (ok2, msgs)
            err.assert(ok2, "fetch failed")
            got.msgs = msgs
          end)
      end)
    end)
    err.assert(#got.uids == 2 and got.uids[1] == 5 and got.uids[2] == 9)
    err.assert(#got.msgs == 2)
    err.assert(got.msgs[1].uid == 5)
    err.assert(got.msgs[1].thrid == "1111222233334444555")
    err.assert(got.msgs[1].header == hdr)
    err.assert(got.msgs[2].uid == 9)
    err.assert(got.msgs[2].header == "Subject: Re")
  end)

  test("append with continuation: " .. name, function ()
    local msg = "Subject: draft\r\n\r\nbody\r\n"
    local got = session({
      GREETING,
      { expect = "T1 APPEND \"[Gmail]/Drafts\" (\\Draft) {" .. #msg .. "}\r\n",
        reply = "+ go\r\n" },
      { expect = msg .. "\r\n", reply = "T1 OK [APPENDUID 1 77] done\r\n" },
    }, ck, function (c, got)
      c.append("[Gmail]/Drafts", "\\Draft", msg, function (ok, res)
        got.ok = ok
        got.res = res
      end)
    end)
    err.assert(got.ok, "append failed")
    err.assert(string.find(got.res.text, "APPENDUID", 1, true))
  end)

  test("list finds drafts: " .. name, function ()
    local got = session({
      GREETING,
      { expect = "T1 LIST \"\" \"*\"\r\n",
        reply = "* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r\n"
          .. "* LIST (\\HasNoChildren \\Drafts) \"/\" \"[Gmail]/Drafts\"\r\n"
          .. "T1 OK done\r\n" },
    }, ck, function (c, got)
      c.drafts_mailbox(function (ok, name2)
        got.ok = ok
        got.name = name2
      end)
    end)
    err.assert(got.ok, "no drafts mailbox")
    err.assert(got.name == "[Gmail]/Drafts")
  end)

end

test("login failure", function ()
  local got = session({
    GREETING,
    { expect = "T1 LOGIN \"u\" \"bad\"\r\n",
      reply = "T1 NO [AUTHENTICATIONFAILED] nope\r\n" },
  }, nil, function (c, got)
    c.login("u", "bad", function (ok, res)
      got.ok = ok
      got.res = res
    end)
  end)
  err.assert(got.ok == false)
  err.assert(got.res.status == "NO")
end)

test("quoting escapes", function ()
  local got = session({
    GREETING,
    { expect = "T1 LOGIN \"u\" \"a\\\"b\\\\c\"\r\n", reply = "T1 OK done\r\n" },
  }, nil, function (c, got)
    c.login("u", "a\"b\\c", function (ok)
      got.ok = ok
    end)
  end)
  err.assert(got.ok, "escaped login failed")
end)

test("serialized queue", function ()
  local order = {}
  session({
    GREETING,
    { expect = "T1 UID SEARCH A\r\n", reply = "* SEARCH 1\r\nT1 OK done\r\n" },
    { expect = "T2 UID SEARCH B\r\n", reply = "* SEARCH 2\r\nT2 OK done\r\n" },
  }, nil, function (c)
    c.search("A", function (ok, uids)
      err.assert(ok)
      order[#order + 1] = uids[1]
    end)
    c.search("B", function (ok, uids)
      err.assert(ok)
      order[#order + 1] = uids[1]
    end)
  end)
  err.assert(order[1] == 1 and order[2] == 2)
end)

local function fake_pull (script)
  return {
    connect = function (opts, done)
      local pending = ""
      local inbox = {}
      local step = 1
      local function queue_replies ()
        while script[step] and not script[step].expect do
          inbox[#inbox + 1] = script[step].reply
          step = step + 1
        end
      end
      local conn
      conn = {
        write = function (d)
          pending = pending .. d
          while script[step] and script[step].expect
            and #pending >= #script[step].expect
            and string.sub(pending, 1, #script[step].expect) == script[step].expect do
            pending = string.sub(pending, #script[step].expect + 1)
            local reply = script[step].reply
            step = step + 1
            if reply then inbox[#inbox + 1] = reply end
            queue_replies()
          end
        end,
        step = function ()
          if #inbox == 0 then
            return true, "timeout"
          end
          opts.data(table.remove(inbox, 1))
          return true
        end,
        close = function ()
          if opts.closed then opts.closed("closed") end
        end,
      }
      done(true, conn)
      queue_replies()
      return conn
    end,
  }
end

test("pull driver pumps to completion", function ()
  local got = {}
  imap(fake_pull({
    GREETING,
    { expect = "T1 LOGIN \"u\" \"p\"\r\n", reply = "T1 OK done\r\n" },
    { expect = "T2 UID SEARCH ALL\r\n",
      reply = "* SEARCH 4 8\r\nT2 OK done\r\n" },
  })).connect({ host = "h", port = 993 }, function (ok, c)
    err.assert(ok, "pull connect failed")
    got.client = c
  end)
  err.assert(got.client, "greeting never pumped")
  got.client.login("u", "p", function (ok)
    got.login = ok
  end)
  err.assert(got.login, "login did not settle before return")
  got.client.search("ALL", function (ok, uids)
    err.assert(ok)
    got.uids = uids
  end)
  err.assert(got.uids and got.uids[1] == 4 and got.uids[2] == 8)
end)

test("pull driver times out a dead command", function ()
  local got = {}
  imap(fake_pull({
    GREETING,
    { expect = "T1 UID SEARCH ALL\r\n" },
  })).connect({
    host = "h", port = 993, step_ms = 10, timeout_ms = 30,
  }, function (ok, c)
    err.assert(ok)
    got.client = c
  end)
  got.client.search("ALL", function (ok, res)
    got.ok = ok
    got.res = res
  end)
  err.assert(got.ok == false, "dead command did not fail")
end)

test("greeting bye fails connect", function ()
  local got = {}
  imap(fake({ { reply = "* BYE overloaded\r\n" } })).connect({
    host = "h", port = 993,
  }, function (ok, res)
    got.ok = ok
    got.res = res
  end)
  err.assert(got.ok == false)
  err.assert(string.find(got.res, "overloaded", 1, true))
end)

test("close fails pending", function ()
  local got = {}
  local drv = fake({
    GREETING,
    { expect = "T1 UID SEARCH A\r\n" },
  })
  imap(drv).connect({ host = "h", port = 993 }, function (ok, c)
    err.assert(ok)
    c.search("A", function (ok2, res)
      got.ok = ok2
      got.res = res
    end)
    c.close()
  end)
  err.assert(got.ok == false)
end)
