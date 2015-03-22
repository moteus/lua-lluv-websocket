------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-lluv-websocket library.
--
------------------------------------------------------------------

local trace -- = print

local uv        = require "lluv"
local ut        = require "lluv.utils"
local tools     = require "websocket.tools"
local frame     = require "lluv.websocket.frame"
local handshake = require "websocket.handshake"

local ok, ssl   = pcall(require, 'lluv.ssl')
if not ok then ssl = nil end

local CONTINUATION = frame.CONTINUATION
local TEXT         = frame.TEXT
local BINARY       = frame.BINARY
local CLOSE        = frame.CLOSE
local PING         = frame.PING
local PONG         = frame.PONG

local FRAME_NAMES = {
  [CONTINUATION ] = 'CONTINUATION';
  [TEXT         ] = 'TEXT';
  [BINARY       ] = 'BINARY';
  [CLOSE        ] = 'CLOSE';
  [PING         ] = 'PING';
  [PONG         ] = 'PONG';
}

local function frame_name(opcode)
  return FRAME_NAMES[opcode] or "UNKNOWN (" .. tostring(opcode) .. ")"
end

local function text(msg)
  if msg then 
    return string.format("[0x%.8X]", #msg) .. (#msg > 50 and (msg:sub(1, 50) .."...") or msg)
  end
  return "[   NULL   ]"
end

local function hex(msg)
  if msg then
    return string.format("[0x%.8X]", #msg) .. 
      string.gsub(msg:sub(1, 50), ".", function(ch)
        return string.format("%.2x ", string.byte(ch))
      end) ..
      (#msg > 50 and "..." or "")
  end
  return "[   NULL   ]"
end

local function is_data_opcode(c)
  return c == TEXT or c == BINARY or c == CONTINUATION
end

local tconcat   = table.concat
local tappend   = function(t, v) t[#t + 1] = v return t end

local ERRORS = {
  [-1] = "EHANDSHAKE";
  [-2] = "EOF";
  [-3] = "ESTATE";
  [-4] = "ENOSUP";
}

local WSError = ut.class() do

for k, v in pairs(ERRORS) do WSError[v] = k end

function WSError:__init(no, name, msg, ext, code, reason)
  self._no     = assert(no)
  self._name   = assert(name or ERRORS[no])
  self._msg    = msg    or ''
  self._ext    = ext    or ''
  self._code   = code   or 1000
  self._reason = reason or ''
  return self
end

function WSError:cat()    return 'WEBSOCKET'  end

function WSError:no()     return self._no     end

function WSError:name()   return self._name   end

function WSError:msg()    return self._msg    end

function WSError:ext()    return self._ext    end

function WSError:code()   return self._code and tostring(self._code) end

function WSError:reason() return self._reason end

function WSError:__tostring()
  return string.format("[%s][%s] %s (%d) - %s %s(%s)",
    self:cat(), self:name(), self:msg(), self:no(), self:ext(),
    self:code(), self:reason()
  )
end

function WSError:__eq(rhs)
  return self._no == rhs._no
end

end

local function WSError_handshake_faild(msg)
  return WSError.new(WSError.EHANDSHAKE, nil, "Handshake failed", msg)
end

local function WSError_EOF(code, reason)
  return WSError.new(WSError.EOF, nil, "end of file", code, reason)
end

local function WSError_ESTATE(msg)
  return WSError.new(WSError.ESTATE, nil, msg)
end

local function WSError_ENOSUP(msg)
  return WSError.new(WSError.ENOSUP, nil, msg)
end

local SizedBuffer = ut.class(ut.Buffer) do
local base = SizedBuffer.__base

function SizedBuffer:__init(buffer)
  assert(base.__init(self))
  self._size = 0

  while buffer do
    local chunk = buffer:read_some()
    if not chunk then break end
    self:append(chunk)
  end

  return self
end

function SizedBuffer:read_line(...)
  error('Unsupported method')
end

function SizedBuffer:read_n(...)
  local data = base.read_n(self, ...)
  if data then self._size = self._size - #data end
  return data
end

function SizedBuffer:read_some()
  local data = base.read_some(self)
  if data then self._size = self._size - #data end
  return data
end

function SizedBuffer:read_all(...)
  local data = base.read_all(self, ...)
  if data then self._size = self._size - #data end
  return data
end

function SizedBuffer:append(data)
  if data then
    self._size = self._size + #data
    base.append(self, data)
  end
  return self
end

function SizedBuffer:prepend(data)
  if data then
    self._size = self._size + #data
    base.prepend(self, data)
  end
  return self
end

function SizedBuffer:size()
  return self._size
end

end

local WSSocket = ut.class() do

-- State:
-- CLOSED not connected or closed handshake
-- WAIT_DATA data transfer mode
-- WAIT_CLOSE client call close method and we wait timeout or response
-- CLOSE_PENDING we recv CLOSE frame but client do not call close method 
--          we wait response and stop read messages
-- CLOSE_PENDING2 we send CLOSE frame but client do not call close method 
--          we wait response and stop read messages.

local function is_sock(s)
  local ts = type(s)
  if ts == 'userdata' then return true end
  if ts ~= 'table' then return false end
  return 
    s.start_read and
    s.write      and
    s.connect    and
    s.shutdown   and
    true
end

function WSSocket:__init(opt, s)
  if is_sock(opt) then s, opt = opt end
  opt = opt or {}

  self._sock      = s or uv.tcp()
  self._frames    = {}
  self._opcode    = nil
  self._origin    = nil
  self._ready     = nil
  self._state     = 'CLOSED' -- no connection
  self._buffer    = nil
  self._wait_size = nil
  self._timeout   = opt.timeout
  self._protocols = opt.protocols

  if opt.utf8 then
    if opt.utf8 == true then
      self._validator = require"lluv.websocket.utf8".validator()
    else
      assert(type(opt.utf8.next)     == 'function')
      assert(type(opt.utf8.validate) == 'function')
      self._validator = opt.utf8
    end
  end

  if opt.ssl then
    if type(opt.ssl.server) == 'function' then
      self._ssl = opt.ssl
    else
      if not ssl then error("Unsupport WSS protocol") end
      self._ssl = assert(ssl.context(opt.ssl))
    end
  end

  self._on_write = function(_, err, cb) cb(self, err) end

  return self
end

local function dns_request(host, cb)
  uv.getaddrinfo(host, nil, {
    socktype = "stream";
    protocol = "tcp";
  }, cb)
end

function WSSocket:connect(url, proto, cb)
  assert(self._sock)

  if self._state ~= "CLOSED" then
    uv.defer(cb, self, WSError_ESTATE("wrong state"))
  end

  self._state = "CONNECTING"

  local key, req

  local protocol, host, port, uri = tools.parse_url(url)

  if protocol ~= 'ws' and protocol ~= 'wss'  then
    return uv.defer(cb, self, WSError_ENOSUP("bad protocol - " .. protocol))
  end

  if protocol == 'wss' then
    if not self._ssl then
      return uv.defer(cb, self, WSError_ENOSUP("unsuported protocol - " .. protocol))
    end
    self._sock = assert(self._ssl:client(self._sock))
  end

  dns_request(host, function(_, err, res)
    if err then return cb(self, err) end

    local ip = res[1]

    self._sock:connect(ip.address, port, function(sock, err)
      if err then return cb(self, err) end

      self:_client_handshake(key, req, cb)
    end)
  end)

  key = tools.generate_key()
  req = handshake.upgrade_request{
    key       = key,
    host      = host,
    port      = port,
    protocols = {proto or ''},
    origin    = self._origin,
    uri       = uri
  }

  return self
end

function WSSocket:write(msg, opcode, cb)
  if type(opcode) == 'function' then cb, opcode = opcode end

  opcode = opcode or TEXT
  local encoded
  if type(msg) == "table" then
    if msg[1] then
      if trace then trace("TX>", self._state, frame_name(opcode), 1 == #msg, self._masked, text(msg[1])) end

      encoded = {
        frame.encode(msg[1], opcode, self._masked, 1 == #msg)
      }

      for i = 2, #msg do
        if #msg[i] > 0 then
          if trace then trace("TX>", self._state, frame_name(opcode), i == #msg, self._masked, text(msg[i])) end

          table.insert(encoded,
            frame.encode(msg[i], CONTINUATION, self._masked, i == #msg)
          )
        end
      end
    else
      if trace then trace("TX>", self._state, frame_name(opcode), true, self._masked, text('')) end
      encoded = frame.encode('', opcode, self._masked)
    end
  else
    if trace then trace("TX>", self._state, frame_name(opcode), true, self._masked, text(msg)) end
    encoded = frame.encode(msg, opcode, self._masked)
  end

  local ok, err
  if not cb then ok, err = self._sock:write(encoded)
  else ok, err = self._sock:write(encoded, self._on_write, cb) end

  if trace then
    if type(encoded) == 'table' then
      encoded = table.concat(encoded)
    end
    trace("WS RAW TX>", os.time(), self._state, hex(encoded))
  end

  if not ok then return nil, err end
  return self
end

function WSSocket:ready(mask, buffer)
  if type(buffer) == "string" then
    self._buffer = SizedBuffer.new()
    self._buffer:append(buffer)
  else
    self._buffer = SizedBuffer.new(buffer)
  end

  self._ready  = true
  self._state  = "WAIT_DATA"
  self._masked = mask
  return self
end

function WSSocket:_client_handshake(key, req, cb)
  self._sock:write(req, function(sock, err)
    if err then
      self._state = 'FAILED'
      self._sock:shutdown()
      return cb(self, err)
    end
  end)

  local expected_accept
  local buffer = ut.Buffer.new('\r\n\r\n')
  self._sock:start_read(function(sock, err, data)
    if err then
      self._state = 'FAILED'
      self._sock:stop_read():shutdown()
      return cb(self, err)
    end

    if trace then trace("WS HS RX>", hex(data)) end

    buffer:append(data)
    local response = buffer:read("*l")
    if not response then return end
    sock:stop_read()

    if trace then trace("WS HS >", "stop read") end

    local headers = handshake.http_headers(response .. '\r\n\r\n')
    if headers['sec-websocket-accept'] ~= expected_accept then
      self._state = 'FAILED'
      self._sock:shutdown()
      err = WSError_handshake_faild(response)
      return cb(self, err)
    end

    self:ready(true, buffer)

    if trace then trace("WS HS DONE>", "buffer size:", self._buffer:size()) end

    cb(self, nil, headers)
  end)

  expected_accept = handshake.sec_websocket_accept(key)
end

function WSSocket:handshake(cb)
  if self._sock.handshake then
    self._sock:handshake(function(sock, err)
      if err then
        self._state = 'FAILED'
        self._sock:shutdown()
        return cb(self, err)
      end
      self:_server_handshake(cb)
    end)
    return
  end

  self:_server_handshake(cb)
end

function WSSocket:_server_handshake(cb)
  local buffer = ut.Buffer.new('\r\n\r\n')

  assert(type(self._protocols) == 'table')

  self._sock:start_read(function(sock, err, data)
    if err then
      self._state = 'FAILED'
      self._sock:stop_read():shutdown()
      return cb(self, err)
    end

    buffer:append(data)
    local request = buffer:read("*l")
    if not request then return end

    sock:stop_read()

    request = request .. '\r\n'

    local response, protocol = handshake.accept_upgrade(request, self._protocols)
    if not response then
      self._state = 'FAILED'
      self._sock:shutdown()
      err = WSError_handshake_faild(request)
      return cb(self, err)
    end

    local headers
    sock:write(response, function(sock, err)
      if err then
        self._state = 'FAILED'
        self._sock:stop_read():shutdown()
        return cb(self, err)
      end

      self:ready(false, buffer)

      cb(self, nil, protocol, headers)
    end)
    headers = handshake.http_headers(request)

  end)
end

function WSSocket:_close(clean, code, reason, cb)
  assert(self._sock)

  if self._timer then
    self._timer:close()
    self._timer = nil
  end

  if cb then
    self._sock:close(function(_, ...) cb(self, clean, code, reason) end)
  else
    self._sock:close()
  end

  self._state, self._sock = 'CLOSED'
end

local function start_close_timer(self, timeout)
  assert(not self._timer)
  assert(self._state == 'WAIT_CLOSE')
  self._timer = uv.timer():start((timeout or 3) * 1000, function()
    self:_close(false, 1006, 'timeout', self._on_close)
  end)
end

function WSSocket:close(code, reason, cb)
  if not self._sock then return end

  if type(code) == 'function' then
    cb, code, reason = code
  elseif type(reason) == 'function' then
    cb, reason = reason
  end

  code   = code or 1000
  reason = reason or ''

  -- not connected or no handshake
  if not self._ready then
    return self:_close(true, code, reason, cb)
  end

  if self._state == 'CLOSED' then
    return self:_close(true, self._code, self._reason, cb)
  end

  -- IO error or interrupted connection
  if (self._state == 'FAILED') or (self._state == 'CONNECTING') then 
    return self:_close(false, code, reason, cb)
  end

  if self._state == 'WAIT_DATA' then -- We in regular data transfer state
    self._state = 'WAIT_CLOSE'

    local encoded = frame.encode_close(code, reason)
    self:write(encoded, CLOSE)

    start_close_timer(self, 3) --! @todo fix hardcoded timeout

    self:_stop_read():_start_read(function()end)

    self._on_close, self._code, self._reason = cb, code, reason

    return
  end

  -- We already recv CLOSE, send CLOSE and now we wait close connection from other side
  if self._state == 'CLOSE_PENDING' or self._state == 'CLOSE_PENDING2' then
    self._state = 'WAIT_CLOSE'

    self._on_close = cb
    start_close_timer(self, 3) --! @todo fix hardcoded timeout
    return
  end

  -- We send CLOSE and wait response
  if self._state == 'WAIT_CLOSE' then
    -- double close
    return nil, 'double close'
  end
end

local function protocol_error(self, code, msg, read_cb, shutdown)
  self._code, self._reason = code or 1002, msg or 'Protocol error'
  local encoded = frame.encode_close(self._code, self._reason)

  if shutdown then -- no wait close response
    self._state = 'CLOSED'
    self:_stop_read()
    self:write(encoded, CLOSE, function()
      if self._sock then self._sock:shutdown() end
    end)
  else
    self._state = 'CLOSE_PENDING2'
    self:write(encoded, CLOSE)
  end

  return read_cb(self, WSError_EOF(self._code, self._reason))
end

local validate_frame = function(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
  if rsv1 or rsv2 or rsv3 then -- Invalid frame
    if self._state == 'WAIT_DATA' then
      protocol_error(self, 1002, "Invalid reserved bit", cb)
    end
    return false
  end
  if self._masked == masked then
    if self._state == 'WAIT_DATA' then
      protocol_error(self, 1002, "Invalid masked bit", cb)
    end
    return false
  end
  return true
end

local CLOSE_CODES = {
  [1000] = true;
  [1001] = true;
  [1002] = true;
  [1003] = true;
  [1007] = true;
  [1008] = true;
  [1009] = true;
  [1010] = true;
  [1011] = true;
}

local on_control = function(self, mode, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
  if not fin then
    if self._state == 'WAIT_DATA' then
      protocol_error(self, 1002, "Fragmented control", cb)
    end
    return
  end

  if opcode == CLOSE then
    if #decoded >= 126 then
      self._code, self._reason = 1002, "Too long payload"
    elseif #decoded > 0 then
      self._code, self._reason = frame.decode_close(decoded)
      local ncode = tonumber(self._code)

      if (not ncode or ncode < 1000)
        or (ncode <  3000 and not CLOSE_CODES[ncode])
      then
        self._code, self._reason = 1002, 'Invalid status code'
      end
    else
      self._code, self._reason = 1000, ''
    end

    if self._state == 'WAIT_CLOSE' then
      return self:_close(true, self._code, self._reason, self._on_close)
    end

    if self._state == 'CLOSE_PENDING2' then
      self._state = 'CLOSED'
      self._sock:_stop_read():shutdown()
      return --! @todo break decode loop in on_raw_data
    end

    self._state = 'CLOSE_PENDING'

    if self._reason and #self._reason > 0 and
      self._validator and not self._validator:validate(self._reason)
    then
      self._code, self._reason = 1007, "Invalid UTF8 character"
    end

    local encoded = frame.encode_close(self._code, self._reason)
    self:write(encoded, CLOSE, function(self, err)
      if self._state == 'CLOSE_PENDING' then
        -- we did not call `close` yet so we just wait
        self._state = 'CLOSED'
      elseif self._state == 'WAIT_CLOSE' then
          -- we call `close` but timeout is not expire
        return self:_close(true, self._code, self._reason, self._on_close)
      end
    end)

    return cb(self, WSError_EOF(self._code, self._reason))
  elseif opcode == PING then
    if self._state == 'WAIT_DATA' then
      if #decoded >= 126 then
        protocol_error(self, 1002, "Too long payload", cb)
      else
        self:write(decoded, PONG)
      end
    end
  elseif opcode == PONG then
    if self._state == 'WAIT_DATA' then
      cb(self, nil, decoded, opcode, true)
    end
  else
    if self._state == 'WAIT_DATA' then
      protocol_error(self, 1002, "Invalid opcode", cb)
    end
  end

end

local on_data = function(self, mode, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
  if self._state ~= 'WAIT_DATA' then
    self._frames, self._opcode = nil
    return
  end

  if not self._opcode then
    if opcode == CONTINUATION then
      return protocol_error(self, 1002, "Unexpected continuation frame", cb, true)
    else
      self._frames, self._opcode = {}, opcode
    end
  else
    if opcode ~= CONTINUATION then
      return protocol_error(self, 1002, "Unexpected data frame", cb, true)
    end
  end

  if self._validator and self._opcode == TEXT then
    if not self._validator:next(decoded, fin) then
      return protocol_error(self, 1007, "Invalid UTF8 character", cb)
    end
  end

  if mode == '*f' then
    cb(self, nil, decoded, opcode, fin)
  else
    if #decoded > 0 then
      tappend(self._frames, decoded)
    end
    if fin == true then
      local f, c = self._frames, self._opcode
      self._frames, self._opcode = nil

      if mode == '*s' then f = table.concat(f) end

      cb(self, nil, f, c, fin)
    end
  end
end

local on_raw_data_1 do

local function next_frame(self)
  local encoded = self._buffer:read_some()

  while encoded do
    local decoded, fin, opcode, rest, masked, rsv1, rsv2, rsv3 = frame.decode(encoded)
    if decoded then
      self._wait_size = nil
      self._buffer:prepend(rest)
      return decoded, fin, opcode, masked, rsv1, rsv2, rsv3
    end

    if self._buffer:size() < fin then
      self._buffer:prepend(encoded)
      self._wait_size = fin + #encoded
      return
    end

    local chunk = self._buffer:read_n(fin)

    encoded = encoded .. chunk
  end
end

on_raw_data_1 = function(self, data, cb, mode)
  if self._wait_size and self._buffer:size() < self._wait_size then
    return
  end

  while self._sock and self._read_cb == cb do
    local decoded, fin, opcode, masked, rsv1, rsv2, rsv3 = next_frame(self)

    if not decoded then break end

    if trace then trace("RX>", self._state, frame_name(opcode), fin, masked, text(decoded), rsv1, rsv2, rsv3) end

    if validate_frame(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3) then
      local handler = is_data_opcode(opcode) and on_data or on_control
      handler(self, mode, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
    end
  end
end

end

local on_raw_data_2 = function(self, data, cb, mode)
  if self._wait_size and self._buffer:size() < self._wait_size then
    return
  end

  local pos, encoded = 1, self._buffer:read_all()

  while self._sock and self._read_cb == cb do
    local decoded, fin, opcode, masked, rsv1, rsv2, rsv3

    decoded, fin, opcode, pos, masked, rsv1, rsv2, rsv3 = frame.decode_by_pos(encoded, pos)
  
    if not decoded then
      local rest = string.sub(encoded, pos)
      self._wait_size = fin
      self._buffer:prepend(rest)
      return
    end
    self._wait_size = nil -- we can set it to 2 because header size >= 2

    if trace then trace("RX>", self._state, frame_name(opcode), fin, masked, text(decoded), rsv1, rsv2, rsv3) end

    if validate_frame(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3) then
      local handler = is_data_opcode(opcode) and on_data or on_control
      handler(self, mode, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
    end
  end
end

local on_raw_data = on_raw_data_2

function WSSocket:_start_read(mode, cb)
  if type(mode) == 'function' then
    cb, mode = mode
  end

  mode = mode or '*s'

  assert(mode == '*t' or mode == '*s' or mode == '*f', mode)

  assert(cb)

  local function do_read(cli, err, data)
    if data then
      if trace then trace("WS RAW RX>", os.time(), self._state, cb, self._buffer:size(), self._wait_size, hex(data)) end
      self._buffer:append(data)
    end

    if self._read_cb ~= cb then return end

    if err then
      if trace then trace("WS RAW RX>", os.time(), self._state, cb, err) end

      self:_stop_read()
      self._sock:shutdown()

      if self._state == 'WAIT_CLOSE' then
        self:_close(false, self._code, self._reason, self._on_close)
      else
        self._state = 'CLOSED'
      end

      return cb(self, err)
    end

    on_raw_data(self, data, cb, mode)
  end

  if self._read_cb then
    if self._read_cb == cb then return end
    self:_stop_read()
  end

  self._read_cb = cb

  if not self._buffer:empty() then
    uv.defer(do_read, self._sock, nil, '')
  end

  self._sock:start_read(do_read)

  return self
end

function WSSocket:start_read(...)
  if self._state ~= 'WAIT_DATA' then return end

  return self:_start_read(...)
end

function WSSocket:_stop_read()
  self._sock:stop_read()
  self._read_cb = nil
  return self
end

function WSSocket:stop_read()
  if self._state ~= 'WAIT_DATA' then return end

  return self:_stop_read()
end

function WSSocket:bind(url, protocols, cb)
  if type(protocols) == 'function' then
    cb, protocols = protocols
  end

  self._protocols = protocols or self._protocols
  if not self._protocols then error("No protocols") end

  if type(self._protocols) == 'string' then self._protocols = {self._protocols} end

  assert(type(self._protocols) == 'table')

  local protocol, host, port, uri = tools.parse_url(url)

  if protocol ~= 'ws' and protocol ~= 'wss'  then
    local err = WSError_ENOSUP("bad protocol - " .. protocol)
    if cb then
      uv.defer(cb, self, err)
      return self
    end
    return nil, err
  end

  if protocol == 'wss' and not self._ssl then
    local err = WSError_ENOSUP("unsuported protocol - " .. protocol)
    if cb then
      uv.defer(cb, self, err)
      return self
    end
    return nil, err
  end

  self._is_wss = (protocol == 'wss')

  local ok, err
  if cb then
    ok, err = self._sock:bind(host, port, function(_, ...) cb(self, ...) end)
  else
    ok, err = self._sock:bind(host, port)
  end
  if not ok then return nil, err end
  return self
end

function WSSocket:accept()
  local cli, err = self._sock:accept()
  if not cli then return nil, err end
  if self._is_wss then cli = assert(self._ssl:server(cli)) end
  return WSSocket.new({
    protocols = self._protocols;
    utf8      = self._validator and self._validator.new();
  }, cli)
end

function WSSocket:listen(cb)
  local ok, err = self._sock:listen(function(_, ...)
    cb(self, ...)
  end)

  if not ok then return nil, err end

  return self
end

function WSSocket:__tostring()
  return "Lua-UV websocket (" .. tostring(self._sock) .. ")"
end

function WSSocket:getsockname()
  return self._sock:getsockname()
end

function WSSocket:getpeername()
  return self._sock:getpeername()
end

end

return {
  new = WSSocket.new;

  TEXT         = TEXT;
  BINARY       = BINARY;
  PING         = PING;
  PONG         = PONG;

  CONTINUATION = CONTINUATION;
  CLOSE        = CLOSE;
}
