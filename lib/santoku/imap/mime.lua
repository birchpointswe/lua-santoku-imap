local str = require("santoku.string")
local arr = require("santoku.array")
local headers = require("santoku.imap.headers")

local function encode_word (s)
  if str.find(s, "[^\32-\126]") then
    return "=?UTF-8?B?" .. str.to_base64(s) .. "?="
  end
  return s
end

local function build (t)
  local out = {}
  local function h (k, v)
    if v and v ~= "" then
      arr.push(out, k, ": ", v, "\r\n")
    end
  end
  h("From", t.from)
  h("To", t.to)
  h("Subject", t.subject and encode_word(t.subject))
  h("Date", t.date)
  h("Message-ID", t.message_id and ("<" .. t.message_id .. ">"))
  h("In-Reply-To", t.in_reply_to and ("<" .. t.in_reply_to .. ">"))
  if t.references and #t.references > 0 then
    local refs = {}
    for i = 1, #t.references do
      arr.push(refs, "<" .. t.references[i] .. ">")
    end
    h("References", arr.concat(refs, " "))
  end
  h("MIME-Version", "1.0")
  h("Content-Type", "text/plain; charset=utf-8")
  h("Content-Transfer-Encoding", "8bit")
  arr.push(out, "\r\n")
  local body = {}
  for i = 1, #(t.paragraphs or {}) do
    local p = str.gsub(t.paragraphs[i], "\r\n", "\n")
    arr.push(body, (str.gsub(p, "\n", "\r\n")))
  end
  arr.push(out, arr.concat(body, "\r\n\r\n"), "\r\n")
  return arr.concat(out)
end

local function decode_cte (data, cte)
  cte = tostring(cte or ""):lower()
  if str.find(cte, "base64", 1, true) then
    local ok, d = pcall(str.from_base64, (str.gsub(data, "%s", "")))
    if ok and d then
      return d
    end
    return ""
  end
  if str.find(cte, "quoted-printable", 1, true) then
    data = str.gsub(data, "=\r?\n", "")
    return (str.gsub(data, "=(%x%x)", function (h)
      return str.char(tonumber(h, 16))
    end))
  end
  return data
end

local function strip_html (s)
  s = str.gsub(s, "<[sS][tT][yY][lL][eE][^>]*>.-</[sS][tT][yY][lL][eE]>", " ")
  s = str.gsub(s, "<[sS][cC][rR][iI][pP][tT][^>]*>.-</[sS][cC][rR][iI][pP][tT]>", " ")
  s = str.gsub(s, "<[bB][rR]%s*/?>", "\n")
  s = str.gsub(s, "</[pP]>", "\n\n")
  s = str.gsub(s, "</[dD][iI][vV]>", "\n")
  s = str.gsub(s, "<[^>]->", "")
  s = str.gsub(s, "&nbsp;", " ")
  s = str.gsub(s, "&amp;", "&")
  s = str.gsub(s, "&lt;", "<")
  s = str.gsub(s, "&gt;", ">")
  s = str.gsub(s, "&quot;", "\"")
  s = str.gsub(s, "&#(%d+);", function (n)
    n = tonumber(n)
    if n and n >= 32 and n < 127 then
      return string.char(n)
    end
    return ""
  end)
  return s
end

local function boundary_of (ctype)
  return str.match(ctype, "boundary%s*=%s*\"([^\"]+)\"")
    or str.match(ctype, "boundary%s*=%s*([^;%s]+)")
end

local function split_parts (body, boundary)
  local delim = "--" .. boundary
  local out = {}
  local pos = str.find(body, delim, 1, true)
  while pos do
    if str.sub(body, pos + #delim, pos + #delim + 1) == "--" then
      break
    end
    local line_end = str.find(body, "\n", pos, true)
    if not line_end then
      break
    end
    local nxt = str.find(body, delim, line_end, true)
    local chunk_end = nxt and (nxt - 1) or #body
    out[#out + 1] = str.sub(body, line_end + 1, chunk_end)
    pos = nxt
  end
  return out
end

local function parse_part (ctype, cte, body, depth)
  ctype = str.lower(tostring(ctype or "text/plain"))
  if str.match(ctype, "^%s*multipart/") then
    if depth >= 4 then
      return nil
    end
    local boundary = boundary_of(ctype)
    if not boundary then
      return nil
    end
    local best_html
    for _, chunk in ipairs(split_parts(body, boundary)) do
      local he = str.find(chunk, "\r?\n\r?\n")
      local hraw = he and str.sub(chunk, 1, he - 1) or ""
      local pbody = he and str.sub(chunk,
        (select(2, str.find(chunk, "^.-\r?\n\r?\n"))) + 1) or chunk
      local ph = headers.parse(hraw)
      local text, kind = parse_part(ph["content-type"],
        ph["content-transfer-encoding"], pbody, depth + 1)
      if text and kind == "plain" then
        return text, "plain"
      end
      if text and not best_html then
        best_html = text
      end
    end
    if best_html then
      return best_html, "html"
    end
    return nil
  end
  if str.match(ctype, "^%s*text/plain") or str.match(ctype, "^%s*$") then
    return decode_cte(body, cte), "plain"
  end
  if str.match(ctype, "^%s*text/html") then
    return strip_html(decode_cte(body, cte)), "html"
  end
  return nil
end

local function extract_text (ctype, cte, raw)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local ok, text = pcall(parse_part, ctype, cte, raw, 0)
  if not ok or not text then
    return nil
  end
  return text
end

local function cut_utf8 (s, max)
  if #s <= max then
    return s
  end
  local cut = max
  while cut > 1 and s:byte(cut + 1)
    and s:byte(cut + 1) >= 0x80 and s:byte(cut + 1) <= 0xBF do
    cut = cut - 1
  end
  return str.sub(s, 1, cut)
end

local function paragraphs (text, opts)
  opts = opts or {}
  local max_len = opts.max_len or 2000
  local max_count = opts.max_count or 64
  local max_total = opts.max_total or 16384
  text = str.gsub(tostring(text or ""), "\r\n", "\n")
  local out = {}
  local total = 0
  local truncated = false
  for block in str.gmatch(text .. "\n\n", "(.-)\n\n+") do
    block = str.gsub(block, "%s+", " ")
    block = str.match(block, "^%s*(.-)%s*$")
    if block ~= "" then
      if #out >= max_count or total >= max_total then
        truncated = true
        break
      end
      if #block > max_len then
        block = cut_utf8(block, max_len)
        truncated = true
      end
      out[#out + 1] = block
      total = total + #block
    end
  end
  if truncated then
    out[#out + 1] = "[truncated]"
  end
  return out
end

return {
  build = build,
  encode_word = encode_word,
  extract_text = extract_text,
  paragraphs = paragraphs,
}
