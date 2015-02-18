local tools     = require 'websocket.tools'
local frame     = require 'websocket.frame'
local handshake = require 'websocket.handshake'
local websocket = require 'websocket'
local uv        = require 'lluv'
local ut        = require 'lluv.utils'
local LOG       = require 'log'.new(
  require'log.writer.stdout'.new(),
  require'log.formatter.concat'.new(' ')
)
local tconcat   = table.concat
local tappend   = function(t, v) t[#t + 1] = v return t end

local clients = {[true] = {}}

local EOF = uv.error(uv.ERROR_UV, uv.EOF)

local function ocall(f, ...)
  if f then return f(...) end
end

local Client = ut.class() do

local TEXT, BINARY, CLOSE = frame.TEXT, frame.BINARY, frame.CLOSE

local send = function(self, msg, opcode, cb)
  local encoded = frame.encode(msg, opcode or TEXT)
  if not cb then return self._sock:write(encoded) end
  return self._sock:write(encoded, cb)
end

local on_error = function(self, err)
  if clients[protocol] ~= nil then clients[protocol][self] = nil end

  ocall(self._on_error, self, err)
  LOG.debug('Websocket server error', err)
end

local on_close = function(self, was_clean, code, reason)
  if clients[protocol] ~= nil then clients[protocol][self] = nil end

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

function Client:__init(sock, protocol)
  self._sock              = assert(sock)
  self._proto             = protocol
  self._state             = 'OPEN'
  self._started           = false
  self._close_timer       = nil
  clients[protocol][self] = true
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

function Client:send(message, opcode)
  return send(self, message, opcode)
end

function Client:broadcast(...)
  for client in pairs(clients[self._proto]) do
    if client._state == 'OPEN' then
      client:send(...)
    end
  end
end

function Client:close(code, reason, timeout)
  if clients[protocol] ~= nil then clients[protocol][self] = nil end

  if not self._started then self:start() end

  if self._state == 'OPEN' then
    self._state = 'CLOSING'
    timeout = (timeout or 3) * 1000 -- msec
    local encoded = frame.encode_close(code or 1000, reason or '')
    send(self, encoded, CLOSE)
    self._close_timer = ut.timer():start(timeout, function(timer)
      on_close(self, false, 1006, 'timeout')
    end)
  end

  return self
end

function Client:start()
  local frames, first_opcode, last = {}

  self._sock:start_read(function(sock, err, data)
    if err then return handle_sock_err(self, err) end

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
  end)

  self._started = true
end

end

local Listener = ut.class() do

local function on_error(self, err)
  ocall(self._on_error, self, err)
  LOG.debug('Websocket listen error', err)
end

local function Handshake(self, sock, cb)
  local buffer = ut.Buffer.new('\r\n\r\n')
  sock:start_read(function(sock, err, data)
    if err then
      LOG.error('Websocket Handshake failed due to socket err:', err)
      return cb(self, err)
    end

    buffer:append(data)
    request = buffer:read("*l")
    if not request then return end

    sock:stop_read()

    local response, protocol = handshake.accept_upgrade(request .. '\r\n', self._protocols)
    if not response then
      LOG.error("Handshake failed, Request:\n", request)
      sock:close()
      return cb(self, "handshake failed", request)
    end

    sock:write(response, function(sock, err)
      if err then
        LOG.error('Websocket client closed while handshake', err)
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

    LOG.info('Handshake done:', protocol)

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

    LOG.info('new client', protocol or 'default')

    local new_client = Client.new(sock, protocol_index)
    protocol_handler(new_client)
    new_client:start(data)
  end)
end

function Listener:__init(opts)
  assert(opts and (opts.protocols or opts.default))

  local sock, err = uv.tcp():bind(opts.interface or '*', opts.port or 80)
  if not sock then return nil, err end

  self._sock = sock

  local handlers, protocols = {}, {}
  if opts.protocols then
    for protocol, handler in pairs(opts.protocols) do
      clients[protocol] = {}
      tappend(protocols, protocol)
      handlers[protocol] = handler
    end
  end
  self._protocols       = protocols
  self._handlers        = handlers
  self._default_handler = opts.default

  sock:listen(function(sock, err)
    local client_sock, err = sock:accept()
    assert(client_sock, tostring(err))

    LOG.info('New connection:', client_sock:getpeername())

    on_new_client(self, client_sock)
  end)
end

function Listener:close(keep_clients)
  if not self._sock then return end

  self._sock:close()
  if not keep_clients then
    for protocol, clients in pairs(clients) do
      for client in pairs(clients) do
        client:close()
      end
    end
  end
  self._sock = nil
end

end

local function listen(...)
  return Listener.new(...)
end

return {
  listen = listen
}