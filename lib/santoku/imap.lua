local str = require("santoku.string")
local arr = require("santoku.array")

local function quote (s)
  local escaped = str.gsub(s, "\\", "\\\\")
  escaped = str.gsub(escaped, "\"", "\\\"")
  return "\"" .. escaped .. "\""
end

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

local function extract_fetch (pieces)
  local toks = tokenize(pieces)
  local out = {}
  local i = 1
  local n = #toks
  while i <= n do
    local t = toks[i]
    if not t.q and t.s == "UID" then
      out.uid = tonumber(toks[i + 1] and toks[i + 1].s)
      i = i + 2
    elseif not t.q and t.s == "X-GM-THRID" then
      out.thrid = toks[i + 1] and toks[i + 1].s
      i = i + 2
    elseif not t.q and t.s == "X-GM-MSGID" then
      out.msgid = toks[i + 1] and toks[i + 1].s
      i = i + 2
    elseif not t.q and (t.s == "BODY" or t.s == "RFC822.HEADER") then
      local is_text = false
      i = i + 1
      if toks[i] and not toks[i].q and toks[i].s == "[" then
        local depth = 1
        i = i + 1
        while i <= n and depth > 0 do
          if not toks[i].q and toks[i].s == "[" then depth = depth + 1 end
          if not toks[i].q and toks[i].s == "]" then depth = depth - 1 end
          if not toks[i].q and toks[i].s == "TEXT" and depth == 1 then
            is_text = true
          end
          i = i + 1
        end
      end
      if toks[i] and not toks[i].q
        and str.match(toks[i].s, "^<%d+>$") then
        i = i + 1
      end
      if toks[i] and toks[i].q then
        if is_text then
          out.body = toks[i].s
        else
          out.header = toks[i].s
        end
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  return out
end

local function extract_list (pieces)
  local toks = tokenize(pieces)
  local attrs = {}
  local depth = 0
  for i = 1, #toks do
    local t = toks[i]
    if not t.q and t.s == "(" then
      depth = depth + 1
    elseif not t.q and t.s == ")" then
      depth = depth - 1
    elseif depth > 0 then
      attrs[str.lower(t.s)] = true
    end
  end
  local last = toks[#toks]
  return { name = last and last.s, attrs = attrs }
end

return function (driver)

  local lib = {}

  lib.connect = function (opts, done)

    local client = {}
    local conn
    local closed = false
    local greeted = false
    local buf = ""
    local need = 0
    local pieces = {}
    local queue = {}
    local active = nil
    local tagn = 0
    local step_ms = opts.step_ms or 1000
    local timeout_ms = opts.timeout_ms or 30000

    local function settle (ok, res)
      local d = done
      done = nil
      if d then d(ok, res) end
    end

    local function fail_all (e)
      local a = active
      active = nil
      if a then a.done(false, { status = "BAD", text = e }) end
      while #queue > 0 do
        local c = table.remove(queue, 1)
        c.done(false, { status = "BAD", text = e })
      end
    end

    local function send_next ()
      if active or #queue == 0 or closed then return end
      active = table.remove(queue, 1)
      conn.write(active.tag .. " " .. active.line .. "\r\n")
    end

    local function pump_until (fn)
      if not (conn and conn.step) then return end
      local waited = 0
      while not fn() and not closed do
        local okstep, e = conn.step(step_ms)
        if not okstep then return end
        if e == "timeout" then
          waited = waited + step_ms
          if waited >= timeout_ms then
            conn.close()
            return
          end
        else
          waited = 0
        end
      end
    end

    local function issue (line, lit, cb)
      tagn = tagn + 1
      local c
      c = { tag = "T" .. tagn, line = line, lit = lit, untagged = {},
        done = function (ok, res)
          c.settled = true
          cb(ok, res)
        end }
      arr.push(queue, c)
      send_next()
      pump_until(function ()
        return c.settled
      end)
    end

    local function unit (ps)
      local first = ps[1].s
      local c1 = str.sub(first, 1, 1)
      if c1 == "+" then
        if active and active.lit then
          local lit = active.lit
          active.lit = nil
          conn.write(lit)
          conn.write("\r\n")
        end
        return
      end
      if c1 == "*" then
        if not greeted then
          greeted = true
          if str.match(first, "^%* BYE") then
            closed = true
            settle(false, str.sub(first, 3))
          else
            settle(true, client)
          end
          return
        end
        if active then
          arr.push(active.untagged, ps)
        end
        return
      end
      local tag, status, rest = str.match(first, "^(%S+) (%S+) ?(.*)$")
      if active and tag == active.tag then
        local a = active
        active = nil
        a.done(status == "OK", { status = status, text = rest,
          untagged = a.untagged })
        send_next()
      end
    end

    local function feed (chunk)
      buf = buf .. chunk
      while true do
        if need > 0 then
          if #buf < need then return end
          arr.push(pieces, { s = str.sub(buf, 1, need), lit = true })
          buf = str.sub(buf, need + 1)
          need = 0
        else
          local e = str.find(buf, "\r\n", 1, true)
          if not e then return end
          local line = str.sub(buf, 1, e - 1)
          buf = str.sub(buf, e + 2)
          local litn = str.match(line, "{(%d+)}$")
          if litn then
            arr.push(pieces, { s = str.sub(line, 1, #line - #litn - 2) })
            need = tonumber(litn)
          else
            arr.push(pieces, { s = line })
            local ps = pieces
            pieces = {}
            unit(ps)
          end
        end
      end
    end

    client.login = function (user, pass, cb)
      issue("LOGIN " .. quote(user) .. " " .. quote(pass), nil, cb)
    end

    local function open_box (cmd, mailbox, cb)
      issue(cmd .. " " .. quote(mailbox), nil, function (ok, res)
        if not ok then return cb(false, res) end
        local out = { exists = 0 }
        for i = 1, #res.untagged do
          local s = res.untagged[i][1].s
          local uv = str.match(s, "^%* OK %[UIDVALIDITY (%d+)%]")
          local un = str.match(s, "^%* OK %[UIDNEXT (%d+)%]")
          local ex = str.match(s, "^%* (%d+) EXISTS")
          if uv then out.uidvalidity = uv end
          if un then out.uidnext = un end
          if ex then out.exists = tonumber(ex) end
        end
        cb(true, out)
      end)
    end

    client.examine = function (mailbox, cb)
      open_box("EXAMINE", mailbox, cb)
    end

    client.select = function (mailbox, cb)
      open_box("SELECT", mailbox, cb)
    end

    client.store = function (set, flags, cb)
      issue("UID STORE " .. set .. " " .. flags, nil, cb)
    end

    client.expunge = function (cb)
      issue("EXPUNGE", nil, cb)
    end

    client.search = function (criteria, cb)
      issue("UID SEARCH " .. criteria, nil, function (ok, res)
        if not ok then return cb(false, res) end
        local uids = {}
        for i = 1, #res.untagged do
          local rest = str.match(res.untagged[i][1].s, "^%* SEARCH ?(.*)$")
          if rest then
            for u in str.gmatch(rest, "%d+") do
              arr.push(uids, tonumber(u))
            end
          end
        end
        cb(true, uids)
      end)
    end

    client.fetch = function (set, items, cb)
      issue("UID FETCH " .. set .. " (" .. items .. ")", nil, function (ok, res)
        if not ok then return cb(false, res) end
        local out = {}
        for i = 1, #res.untagged do
          local ps = res.untagged[i]
          if str.match(ps[1].s, "^%* %d+ FETCH ") then
            arr.push(out, extract_fetch(ps))
          end
        end
        cb(true, out)
      end)
    end

    client.append = function (mailbox, flags, message, cb)
      issue("APPEND " .. quote(mailbox)
        .. (flags and (" (" .. flags .. ")") or "")
        .. " {" .. #message .. "}", message, cb)
    end

    client.list = function (cb)
      issue("LIST \"\" \"*\"", nil, function (ok, res)
        if not ok then return cb(false, res) end
        local out = {}
        for i = 1, #res.untagged do
          local ps = res.untagged[i]
          if str.match(ps[1].s, "^%* LIST ") then
            arr.push(out, extract_list(ps))
          end
        end
        cb(true, out)
      end)
    end

    client.drafts_mailbox = function (cb)
      client.list(function (ok, boxes)
        if not ok then return cb(false, boxes) end
        for i = 1, #boxes do
          if boxes[i].attrs["\\drafts"] then
            return cb(true, boxes[i].name)
          end
        end
        cb(false, { status = "NO", text = "no drafts mailbox" })
      end)
    end

    client.logout = function (cb)
      issue("LOGOUT", nil, function (ok, res)
        closed = true
        cb(ok, res)
      end)
    end

    client.close = function ()
      closed = true
      if conn then conn.close() end
    end

    driver.connect({
      host = opts.host,
      port = opts.port,
      data = feed,
      closed = function (e)
        closed = true
        if done then
          settle(false, e or "closed")
        else
          fail_all(e or "closed")
        end
      end,
    }, function (ok, c)
      if not ok then
        settle(false, c)
        return
      end
      conn = c
    end)

    pump_until(function ()
      return greeted
    end)

  end

  return lib

end
