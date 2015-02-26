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

function WSError:code()   return self._code   end

function WSError:reason() return self._reason end

function WSError:__tostring()
  return string.format("[%s][%s] %s (%d) - %s %d(%s)",
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

    cb(self)
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

    local response, protocol = handshake.accept_upgrade(request .. '\r\n', self._protocols)
    if not response then
      self._state = 'FAILED'
      self._sock:shutdown()
      err = WSError_handshake_faild(request)
      return cb(self, err)
    end

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

      cb(self, nil, protocol)
    end)
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

  self._sock = nil
end

local function start_close_timer(self, timeout)
  assert(not self._timer)
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
    return self:_close(true, self._code, self._reason, self._on_close)
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
  if self._state == "CLOSE_PENDING" then
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

local on_data = function(self, data, cb)
  local encoded = (self._tail or '') .. data
  while self._sock and self._reading do
    local decoded, fin, opcode, rest = frame.decode(encoded)

    if not decoded then break end
    if not self._opcode then self._opcode = opcode end
    tappend(self._frames, decoded)
    encoded = rest

    if fin == true then
      local f, c = tconcat(self._frames), self._opcode
      self._frames, self._opcode = {}

      if c == CLOSE then
        self._code, self._reason = frame.decode_close(f)

        if self._state == 'WAIT_CLOSE' then
          return self:_close(true, self._code, self._reason, self._on_close)
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

        cb(self, WSError_EOF(self._code, self._reason))
      elseif c == PING then self:write(f, PONG)
      elseif self._state == 'WAIT_DATA' then
        cb(self, nil, f, c, true)
      end
    end
  end
  self._tail = encoded
end

function WSSocket:_start_read(cb)
  self._sock:start_read(function(sock, err, data)
    if err then
      self:_stop_read()
      self._sock:shutdown()
      return cb(self, err)
    end

    on_data(self, data, cb)
  end)

  self._reading = true

  if self._tail and #self._tail > 0 then
    uv.defer(on_data, self, '', cb)
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
}
