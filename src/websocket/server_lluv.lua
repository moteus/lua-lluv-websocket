local tools     = require 'websocket.tools'
local frame     = require 'websocket.frame'
local handshake = require 'websocket.handshake'
local websocket = require 'websocket'
local uv        = require 'lluv'
local ut        = require 'lluv.utils'
local ok, ssl   = pcall(require, 'lluv.ssl')
if not ok then ssl = nil end

local tconcat   = table.concat
local tappend   = function(t, v) t[#t + 1] = v return t end
local DummyLogger do
  local dummy = function() end

  DummyLogger = {
    info    = dummy;
    warning = dummy;
    error   = dummy;
    debug   = dummy;
    trace   = dummy;
  }
end

local EOF = uv.error(uv.ERROR_UV, uv.EOF)

local function ocall(f, ...)
  if f then return f(...) end
end

local Client = ut.class() do

local TEXT, BINARY, CLOSE = frame.TEXT, frame.BINARY, frame.CLOSE

local send     = function(self, msg, opcode, cb)
  local encoded = frame.encode(msg, opcode or TEXT)
  if not cb then return self._sock:write(encoded) end
  return self._sock:write(encoded, cb)
end

local on_error = function(self, err)
  if self._clients[self._proto] ~= nil then self._clients[self._proto][self] = nil end

  ocall(self._on_error, self, err)
end

local on_close = function(self, was_clean, code, reason)
  if self._clients[self._proto] ~= nil then self._clients[self._proto][self] = nil end

  if self._close_timer then
    self._close_timer:close()
    self._close_timer = nil
  end

  self._state = 'CLOSED'
  self._sock:close(function()
    ocall(self._on_close, self, was_clean, code, reason or '')
  end)
end

local handle_sock_err = function(self, err)
  if err == EOF then
    if self._state ~= 'CLOSED' then
      on_close(self, false, 1006, '')
    end
  else
    on_error(self, err)
  end
end

local on_message = function(self, message, opcode)
  if opcode == TEXT or opcode == BINARY then
    return ocall(self._on_message, self, message, opcode)
  end

  if opcode == CLOSE then
    if self._state == 'CLOSING' then
      return on_close(self, true, 1006, '')
    end

    self._state = 'CLOSING'
    local code, reason = frame.decode_close(message)
    local encoded = frame.encode_close(code)
    send(self, encoded, CLOSE, function(sock, err)
      if err then return handle_sock_err(self, err) end
      on_close(self, true, code or 1006, reason)
    end)
  end
end

function Client:__init(listener, sock, protocol)
  self._sock                    = assert(sock)
  self._proto                   = protocol
  self._state                   = 'OPEN'
  self._started                 = false
  self._close_timer             = nil
  self._logger                  = listener:logger()
  self._clients                 = listener._clients -- reference to all clients on server
  self._clients[protocol][self] = true -- register self on server
  return self
end

function Client:on_error(handler)
  self._on_error = handler
  return self
end

function Client:on_message(handler)
  self._on_message = handler
  return self
end

function Client:on_close(handler)
  self._on_close = handler
  return self
end

function Client:send(message, opcode, cb)
  if cb then return send(self, message, opcode, function(sock, err)
    cb(self, err)
  end) end
  return send(self, message, opcode)
end

function Client:broadcast(...)
  for client in pairs(self._clients[self._proto]) do
    if client._state == 'OPEN' then
      client:send(...)
    end
  end
end

function Client:close(code, reason, timeout)
  if self._clients[self._proto] ~= nil then self._clients[self._proto][self] = nil end

  if not self._started then self:start() end

  if self._state == 'OPEN' then
    self._state = 'CLOSING'
    timeout = (timeout or 3) * 1000 -- msec
    local encoded = frame.encode_close(code or 1000, reason or '')
    send(self, encoded, CLOSE)
    self._close_timer = uv.timer():start(timeout, function(timer)
      on_close(self, false, 1006, 'timeout')
    end)
  end

  return self
end

function Client:start(last)
  local frames, first_opcode = {}

  local on_data = function(self, data)
    local encoded = (last or '') .. data

    while self._state == 'OPEN' do
      local decoded, fin, opcode, rest = frame.decode(encoded)

      if not decoded then break end
      if not first_opcode then first_opcode = opcode end
      tappend(frames, decoded)
      encoded = rest

      if fin == true then
        on_message(self, tconcat(frames), first_opcode)
        frames, first_opcode = {}
      end
    end

    last = encoded
  end

  self._sock:start_read(function(sock, err, data)
    if err then return handle_sock_err(self, err) end
    on_data(self, data)
  end)

  -- if we have some data from handshake
  if last then uv.defer(on_data, self, '') end

  self._started = true
end

end

local Listener = ut.class() do

local function on_error(self, err)
  self:logger().error('Websocket listen error:', err)
  ocall(self._on_error, self, err)
end

local function Handshake(self, sock, cb)
  local buffer = ut.Buffer.new('\r\n\r\n')
  sock:start_read(function(sock, err, data)
    if err then
      self:logger().error('Websocket Handshake failed due to socket err:', err)
      return cb(self, err)
    end

    buffer:append(data)
    local request = buffer:read("*l")
    if not request then return end

    sock:stop_read()

    local response, protocol = handshake.accept_upgrade(request .. '\r\n', self._protocols)
    if not response then
      self:logger().error("Handshake failed, Request:\n", request)
      sock:close()
      return cb(self, "handshake failed", request)
    end

    sock:write(response, function(sock, err)
      if err then
        self:logger().error('Websocket client closed while handshake', err)
        sock:close()
        return cb(self, err)
      end
      cb(self, nil, sock, protocol, buffer:read("*a"))
    end)
  end)
end

local function on_new_client(self, cli)
  Handshake(self, cli, function(self, err, sock, protocol, data)
    if err then
      return on_error(self, 'Websocket Handshake failed: ' .. tostring(err))
    end

    self:logger().info('Handshake done:', protocol)

    local protocol_handler, protocol_index
    if protocol and self._handlers[protocol] then
      protocol_index   = protocol
      protocol_handler = self._handlers[protocol]
    elseif self._default_protocol then
      -- true is the 'magic' index for the default handler
      protocol_index   = true
      protocol_handler = self._default_handler
    else
      sock:close()
      return on_error(self, 'Websocket Handshake failed: bad protocol - ' .. tostring(protocol))
    end

    self:logger().info('new client', protocol or 'default')

    local new_client = Client.new(self, sock, protocol_index)
    protocol_handler(new_client)
    new_client:start(data)
  end)
end

function Listener:__init(opts)
  assert(opts and (opts.protocols or opts.default))

  self._clients         = {[true] = {}}

  local handlers, protocols = {}, {}
  if opts.protocols then
    for protocol, handler in pairs(opts.protocols) do
      self._clients[protocol] = {}
      tappend(protocols, protocol)
      handlers[protocol] = handler
    end
  end

  self._protocols       = protocols
  self._handlers        = handlers
  self._default_handler = opts.default

  self._logger          = opts.logger or DummyLogger

  local ssl_ctx
  if opts.ssl then
    if not ssl then error("Unsupport WSS protocol") end
    if type(opts.ssl.server) == 'function' then
      ssl_ctx = opts.ssl
    else
      ssl_ctx = assert(ssl.context(opts.ssl))
    end
  end
  self._ssl = ssl_ctx

  local sock
  if self._ssl then
    sock = self._ssl:server()
  else
    sock = uv.tcp()
  end

  local ok, err = sock:bind(opts.interface or '*', opts.port or 80)
  if not ok then
    sock:close()
    return nil, err
  end

  self._sock = sock

  local on_accept
  if self._ssl then
    on_accept = function(sock)
      sock:handshake(function(sock, err)
        if err then
          sock:close()
          return on_error(self, 'SSL Handshake failed: ' .. tostring(err))
        end
        on_new_client(self, sock)
      end)
    end
  else
    on_accept = function(sock)
      on_new_client(self, sock)
    end
  end

  sock:listen(function(sock, err)
    local client_sock, err = sock:accept()
    assert(client_sock, tostring(err))

    self:logger().info('New connection:', client_sock:getpeername())

    on_accept(client_sock)
  end)

  return self
end

function Listener:close(keep_clients)
  if not self._sock then return end

  self._sock:close()
  if not keep_clients then
    for protocol, clients in pairs(self._clients) do
      for client in pairs(clients) do
        client:close()
      end
    end
  end
  self._sock = nil
end

function Listener:logger()
  return self._logger
end

function Listener:set_logger(logger)
  self._logger = logger or DummyLogger
  return self
end

end

local function listen(...)
  return Listener.new(...)
end

return {
  listen = listen
}