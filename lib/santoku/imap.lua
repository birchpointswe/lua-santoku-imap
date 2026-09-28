local str = require("santoku.string")
local arr = require("santoku.array")
local profile = require("santoku.profile")
local tokens = require("santoku.imap.tokens")
local bodystructure = require("santoku.imap.bodystructure")

local is_open = tokens.is_open
local is_close = tokens.is_close
local read_tree = tokens.read_tree

local function quote (s)
  local escaped = str.gsub(s, "\\", "\\\\")
  escaped = str.gsub(escaped, "\"", "\\\"")
  return "\"" .. escaped .. "\""
end

local tokenize = profile.wrapped("imap.tokenize", tokens.tokenize)

local function read_section (toks, i)
  local out = {}
  local glue = ""
  local depth = 1
  i = i + 1
  while toks[i] and depth > 0 do
    local t = toks[i]
    if not t.q and t.s == "[" then
      depth = depth + 1
    elseif not t.q and t.s == "]" then
      depth = depth - 1
    end
    if depth > 0 then
      if is_open(t) then
        arr.push(out, glue, "(")
        glue = ""
      elseif is_close(t) then
        arr.push(out, ")")
        glue = " "
      else
        arr.push(out, glue, t.s)
        glue = " "
      end
    end
    i = i + 1
  end
  return str.upper(arr.concat(out)), i
end

local function part_value (toks, i)
  local t = toks[i]
  if t and not t.q and str.match(t.s, "^<%d+>$") then
    i = i + 1
    t = toks[i]
  end
  if not t then
    return nil, i
  end
  if t.q or str.upper(t.s) ~= "NIL" then
    return t.s, i + 1
  end
  return nil, i + 1
end

local function set_of (list, map)
  local out = {}
  if type(list) == "table" then
    for j = 1, #list do
      local v = list[j]
      if type(v) == "string" then
        out[map and map(v) or v] = true
      end
    end
  end
  return out
end

local function extract_fetch (pieces)
  local toks = tokenize(pieces)
  local items, parts = {}, {}
  local out = { items = items, parts = parts }
  local i = 1
  while toks[i] and not is_open(toks[i]) do
    i = i + 1
  end
  i = i + 1
  while toks[i] and not is_close(toks[i]) do
    local t = toks[i]
    i = i + 1
    if not t.q then
      local key = str.upper(t.s)
      if (key == "BODYSTRUCTURE" or key == "BODY") and is_open(toks[i]) then
        out.structure, i = bodystructure.parse(toks, i)
      elseif key == "BODY" and toks[i] and not toks[i].q and toks[i].s == "[" then
        local section, val
        section, i = read_section(toks, i)
        val, i = part_value(toks, i)
        parts[section] = val
        if str.match(section, "^HEADER") then
          out.header = val
        else
          out.body = val
        end
      else
        local val
        val, i = read_tree(toks, i)
        items[key] = val
        if key == "RFC822.HEADER" then
          out.header = val
        elseif key == "RFC822.TEXT" or key == "RFC822" then
          out.body = val
        end
      end
    end
  end
  out.uid = tonumber(items.UID)
  out.thrid = items["X-GM-THRID"]
  out.msgid = items["X-GM-MSGID"]
  out.internaldate = items.INTERNALDATE
  out.size = tonumber(items["RFC822.SIZE"])
  out.flags = set_of(items.FLAGS, str.lower)
  out.labels = set_of(items["X-GM-LABELS"])
  return out
end

extract_fetch = profile.wrapped("imap.extract_fetch", extract_fetch)

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
    local pos = 1
    local parts = {}
    local plen = 0
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
        local _, c = arr.shift(queue)
        c.done(false, { status = "BAD", text = e })
      end
    end

    local function send_next ()
      if active or #queue == 0 or closed then return end
      active = select(2, arr.shift(queue))
      conn.write(active.tag .. " " .. active.line .. "\r\n")
    end

    local function pump_until (fn)
      if not (conn and conn.step) then return end
      local waited = 0
      while not fn() and not closed do
        local okstep, e = profile.timed("imap.step", conn.step, step_ms)
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

    local function avail ()
      return #buf - pos + 1 + plen
    end

    local function merge ()
      if #parts == 0 then
        return
      end
      local out = { pos > 1 and str.sub(buf, pos) or buf }
      for i = 1, #parts do
        out[i + 1] = parts[i]
      end
      buf = arr.concat(out)
      pos = 1
      parts = {}
      plen = 0
    end

    local feed = profile.wrapped("imap.feed", function (chunk)
      arr.push(parts, chunk)
      plen = plen + #chunk
      while true do
        if need > 0 then
          if avail() < need then return end
          merge()
          local lit = str.sub(buf, pos, pos + need - 1)
          arr.push(pieces, { s = lit, lit = true })
          pos = pos + need
          need = 0
        else
          merge()
          local e = str.find(buf, "\r\n", pos, true)
          if not e then return end
          local line = str.sub(buf, pos, e - 1)
          pos = e + 2
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
    end)

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
