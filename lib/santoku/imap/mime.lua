local str = require("santoku.string")
local arr = require("santoku.array")

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

return {
  build = build,
  encode_word = encode_word,
}
