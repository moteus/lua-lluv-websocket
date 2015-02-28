------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-lluv-ssl library.
--
------------------------------------------------------------------

local uv        = require "lluv"
local ut        = require "lluv.utils"
local tools     = require "websocket.tools"
local frame     = require "websocket.frame"
local handshake = require "websocket.handshake"

local ok, ssl   = pcall(require, 'lluv.ssl')
if not ok then ssl = nil end

local CONTINUATION = frame.CONTINUATION
local TEXT         = frame.TEXT
local BINARY       = frame.BINARY
local CLOSE        = frame.CLOSE
local PING         = frame.PING
local PONG         = frame.PONG

local function is_valid_fin_opcode(c)
  return c == TEXT or
         c == BINARY or
         c == PING or
         c == PONG or
         c == CLOSE
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
  self._tail      = nil
  self._origin    = nil
  self._ready     = nil
  self._state     = 'CLOSED' -- no connection
  self._timeout   = opt.timeout
  self._protocols = opt.protocols

  if opt.ssl then
    if type(opt.ssl.server) == 'function' then
      self._ssl = opt.ssl
    else
      if not ssl then error("Unsupport WSS protocol") end
      self._ssl = assert(ssl.context(opt.ssl))
    end
  end

  return self
end

local function dns_request(host, cb)
  uv.getaddrinfo(host, port, {
    family   = "inet";
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
  local encoded = frame.encode(msg, opcode or TEXT, self._masked)
  local ok, err
  if not cb then ok, err = self._sock:write(encoded)
  else ok, err = self._sock:write(encoded, function(_, ...) cb(self, ...) end) end
  if not ok then return nil, err end
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

    buffer:append(data)
    local response = buffer:read("*l")
    if not response then return end
    sock:stop_read()

    local headers = handshake.http_headers(response .. '\r\n\r\n')
    if headers['sec-websocket-accept'] ~= expected_accept then
      self._state = 'FAILED'
      self._sock:shutdown()
      err = WSError_handshake_faild(response)
      return cb(self, err)
    end

    self._tail   = buffer:read("*a")
    self._ready  = true
    self._state  = "WAIT_DATA"
    self._masked = true

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

      self._tail   = buffer:read("*a")
      self._ready  = true
      self._state  = "WAIT_DATA"
      self._masked = false

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

local function protocol_error(self, msg, read_cb, shutdown)
  self._code, self._reason = 1002, msg or 'Protocol error'
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
      protocol_error(self, "Invalid reserved bit", cb)
    end
    return false
  end
  return true
end

local on_control = function(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
  if not fin then
    if self._state == 'WAIT_DATA' then
      protocol_error(self, "Fragmented control", cb)
    end
    return
  end

  if opcode == CLOSE then
    self._code, self._reason = frame.decode_close(decoded)

    if self._state == 'WAIT_CLOSE' then
      return self:_close(true, self._code, self._reason, self._on_close)
    end

    if self._state == 'CLOSE_PENDING2' then
      self._state = 'CLOSED'
      self._sock:_stop_read():shutdown()
      return --! @todo break decode loop in on_raw_data
    end

    self._state = 'CLOSE_PENDING'

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
        protocol_error(self, "Too long payload", cb)
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
      protocol_error(self, "Invalid opcode", cb)
    end
  end

end

local on_data = function(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
  if self._state ~= 'WAIT_DATA' then
    self._frames, self._opcode = nil
    return
  end

  if not self._opcode then
    if opcode == CONTINUATION then
      return protocol_error(self, "Unexpected continuation frame", cb, true)
    else
      self._frames, self._opcode = {}, opcode
    end
  else
    if opcode ~= CONTINUATION then
      return protocol_error(self, "Unexpected data frame", cb, true)
    end
  end

  tappend(self._frames, decoded)

  if fin == true then
    local f, c = tconcat(self._frames), self._opcode
    self._frames, self._opcode = nil

    cb(self, nil, f, c, true)
  end
end

local on_raw_data = function(self, data, cb)
  local encoded = (self._tail or '') .. data
  -- print("TAIL:", hex(self._tail))
  -- print("DATA:", hex(data))
  while self._sock and self._reading do
    local decoded, fin, opcode, rest, masked, rsv1, rsv2, rsv3 = frame.decode(encoded)

    if not decoded then break end
    -- print("RX>", self._state, decoded, fin, opcode, rsv1, rsv2, rsv3 )

    if validate_frame(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3) then
      local handler = is_data_opcode(opcode) and on_data or on_control
      handler(self, cb, decoded, fin, opcode, masked, rsv1, rsv2, rsv3)
    end
    encoded = rest
  end
  self._tail = encoded
end

function WSSocket:_start_read(cb)
  self._sock:start_read(function(sock, err, data)
    if err then
      self:_stop_read()
      self._sock:shutdown()

      if self._state == 'WAIT_CLOSE' then
        self:_close(false, self._code, self._reason, self._on_close)
      else
        self._state = 'CLOSED'
      end

      return cb(self, err)
    end

    on_raw_data(self, data, cb)
  end)

  self._reading = true

  if self._tail and #self._tail > 0 then
    uv.defer(on_raw_data, self, '', cb)
  end

  return self
end

function WSSocket:start_read(...)
  if self._state ~= 'WAIT_DATA' then return end

  return self:_start_read(...)
end

function WSSocket:_stop_read()
  self._sock:stop_read()
  self._reading = false
  return self
end

function WSSocket:stop_read()
  if self._state ~= 'WAIT_DATA' then return end

  return self:_stop_read()
end

function WSSocket:bind(host, port, cb)
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
  if self._ssl then cli = assert(self._ssl:server(cli)) end
  return WSSocket.new({protocols = self._protocols}, cli)
end

function WSSocket:listen(protocols, cb)
  if type(protocols) == 'function' then
    cb, protocols = protocols
  end

  self._protocols = protocols or self._protocols
  if not self._protocols then error("No protocols") end

  if type(self._protocols) == 'string' then self._protocols = {self._protocols} end

  assert(type(self._protocols) == 'table')

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
