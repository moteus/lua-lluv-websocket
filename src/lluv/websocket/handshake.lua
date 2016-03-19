-- Code based on https://github.com/lipp/lua-websockets

local split = require 'lluv.websocket.split'
local tools = require 'lluv.websocket.tools'
local sha1, base64 = tools.sha1, tools.base64

local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

local decode_header, encode_header

local sec_websocket_accept = function(sec_websocket_key)
  local a = sec_websocket_key..guid
  local sha1 = sha1(a)
  assert((#sha1 % 2) == 0)
  return base64.encode(sha1)
end

local http_headers = function(request)
  local headers = {}
  if not request:match('.*HTTP/1%.1') then
    return headers
  end

  request = request:match('[^\r\n]+\r\n(.*)')
  local empty_line
  for line in request:gmatch('[^\r\n]*\r\n') do
    local name,val = line:match('([^%s]+)%s*:%s*([^\r\n]+)')
    if name and val then
      name = name:lower()
      if not name:match('sec%-websocket') then
        val = val:lower()
      end
      if not headers[name] then
        headers[name] = val
      else
        headers[name] = headers[name]..','..val
      end
    elseif line == '\r\n' then
      empty_line = true
    else
      assert(false,line..'('..#line..')')
    end
  end
  return headers,request:match('\r\n\r\n(.*)')
end

local upgrade_request = function(req)
  local format = string.format
  local lines = {
    format('GET %s HTTP/1.1',req.uri or ''),
    format('Host: %s',req.host),
    'Upgrade: websocket',
    'Connection: Upgrade',
    format('Sec-WebSocket-Key: %s',req.key),
    format('Sec-WebSocket-Protocol: %s',table.concat(req.protocols,', ')),
    'Sec-WebSocket-Version: 13',
  }
  if req.origin then
    lines[#lines + 1] = string.format('Origin: %s',req.origin)
  end

  if req.port and req.port ~= 80 then
    lines[2] = format('Host: %s:%d',req.host,req.port)
  end

  if req.extensions and #req.extensions > 0 then
    lines[#lines + 1] = 'Sec-WebSocket-Extensions: ' .. req.extensions
  end

  lines[#lines + 1] = '\r\n'
  return table.concat(lines,'\r\n')
end

local accept_upgrade = function(request, protocols)
  local headers = http_headers(request)
  if headers['upgrade'] ~= 'websocket' or
  not headers['connection'] or
  not headers['connection']:match('upgrade') or
  headers['sec-websocket-key'] == nil or
  headers['sec-websocket-version'] ~= '13' then
    return nil,'HTTP/1.1 400 Bad Request\r\n\r\n'
  end

  local prot

  local require_protocols = decode_header(headers['sec-websocket-protocol'])
  if require_protocols then
    for _, protocol in ipairs(require_protocols) do
      for _,supported in ipairs(protocols) do
        if supported == protocol[1] then
          prot = protocol[1]
          break
        end
      end
      if prot then break end
    end
  end

  local accept_key = sec_websocket_accept(headers['sec-websocket-key'])
  local connection = headers['connection']
  local extensions = headers['sec-websocket-extensions']

  local lines = {
    'HTTP/1.1 101 Switching Protocols',
    'Upgrade: websocket',
    'Connection: '           .. connection,
    'Sec-WebSocket-Accept: ' .. accept_key,
  }

  if prot then
    lines[#lines + 1] = 'Sec-WebSocket-Protocol: ' .. prot
  end

  return lines, prot, extensions
end

local function tappend(t, v)
  t[#t+1]=v
  return t
end

local function happend(t, v)
  if not t then return v end
  if type(t)=='table' then
    return tappend(t, v)
  end
  return {t, v}
end

local function trim(s)
  return string.match(s, "^%s*(.-)%s*$")
end

local function itrim(t)
  for i = 1, #t do t[i] = trim(t[i]) end
  return t
end

local function prequre(...)
  local ok, mod = pcall(require, ...)
  if not ok then return nil, mod, ... end
  return mod, ...
end

local function unquote(s)
  if string.sub(s, 1, 1) == '"' then
    s = string.sub(s, 2, -2)
    s = string.gsub(s, "\\(.)", "%1")
  end
  return s
end

local function enqute(s)
  if string.find(s, '[ ",;]') then
    s = '"' .. string.gsub(s, '"', '\\"') .. '"'
  end
  return s
end

local function decode_header_native(str)
  -- does not support `,` or `;` in values

  if not str then return end

  local res = {}
  for ext in split.iter(str, "%s*,%s*") do
    local name, tail = split.first(ext, '%s*;%s*')
    if #name > 0 then
      local opt  = {}
      if tail then
        for param in split.iter(tail, '%s*;%s*') do
          local k, v = split.first(param, '%s*=%s*')
          opt[k] = happend(opt[k], v and unquote(v) or true)
        end
      end
      res[#res + 1] = {name, opt}
    end
  end

  return res
end

local lpeg, decode_header_lpeg = (prequre 'lpeg') if lpeg then
  local P, C, Cs, Ct, Cp = lpeg.P, lpeg.C, lpeg.Cs, lpeg.Ct, lpeg.Cp
  local nl          = P('\n')
  local any         = P(1)
  local eos         = P(-1)
  local quot        = '"'

  -- split params
  local unquoted    = (any - (nl + P(quot) + P(',') + eos))^1
  local quoted      = P(quot) * ((P('\\') * P(quot) + (any - P(quot)))^0) * P(quot)
  local field       = Cs( (quoted + unquoted)^0 )
  local params      = Ct(field * ( P(',') * field )^0) * (nl + eos) * Cp()

  -- split options
  local quoted_pair = function (ch) return ch:sub(2) end
  local unquoted    = (any - (nl + P(quot) + P(';') + P('=') + eos))^1
  local quoted      = (P(quot) / '') * (
    (
      P('\\') * any / quoted_pair +
      (any - P(quot))
    )^0
  ) * (P(quot) / '')
  local kv          = unquoted * P'=' * (quoted + unquoted)
  local field       = Cs(kv + unquoted)
  local options     = Ct(field * ( P(';') * field )^0) * (nl + eos) * Cp()

  function decode_header_lpeg(str)
    if not str then return str end

    local h = params:match(str)
    if not h then return nil end

    local res = {}
    for i = 1, #h do
      local o = options:match(h[i])
      if o then
        itrim(o)
        local name, opt = o[1], {}
        for j = 2, #o do
          local k, v = split.first(o[j], '%s*=%s*')
          opt[k] = happend(opt[k], v or true)
        end
        res[#res + 1] = {name, opt}
      end
    end

    return res
  end
end

decode_header = decode_header_lpeg or decode_header_native

local function encode_header_options(name, options)
  local str = name
  if options then
    for k, v in pairs(options) do
      if v == true then str = str .. '; ' .. k
      elseif type(v) == 'table' then
        for _, v in ipairs(v) do
          if v == true then str = str .. '; ' .. k
          else str = str .. '; ' .. k .. '=' .. enqute(tostring(v)) end
        end
      else str = str .. '; ' .. k .. '=' .. enqute(tostring(v)) end
    end
  end
  return str
end

function encode_header(t)
  if not t then return end

  local res = {}
  for _, val in ipairs(t) do
    tappend(res, encode_header_options(val[1], val[2]))
  end

  return table.concat(res, ', ')
end

return {
  sec_websocket_accept = sec_websocket_accept,
  http_headers = http_headers,
  accept_upgrade = accept_upgrade,
  upgrade_request = upgrade_request,
  decode_header = decode_header,
  encode_header = encode_header,

  -- NOT PUBLIC API
  _decode_header_lpeg = decode_header_lpeg;
  _decode_header_native = decode_header_native;
}