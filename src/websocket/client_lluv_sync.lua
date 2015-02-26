local uv     = require'lluv'
local ut     = require'lluv.utils'
local socket = require'lluv.luasocket'
local sync   = require'websocket.sync'

local ssl, sslsocket do
  local ok
  ok, sslsocket = pcall(require, 'lluv.ssl.luasocket')
  if not ok then sslsocket = nil
  else ssl = require'lluv.ssl' end
end

local Client = ut.class() do

function Client:__init(ws)
  sync.extend(self)
  self._ws = ws or {}
  self.state = self.state or 'CLOSED' --! @todo remove
  return self
end

function Client:sock_connect(host, port)
  self._sock = socket.tcp()

  if self._ws.timeout then
    self._sock:settimeout(self._ws.timeout)
  end

  local ok, err = self._sock:connect(host,port)
  if not ok then
    self._sock:close()
    self._sock = nil
    return nil, err
  end

  return self
end

function Client:sock_send(msg)
  local ok, err = self._sock:send(msg)
  if ok then return #msg end
  return nil, err
end

function Client:sock_receive(...)
  return self._sock:receive(...)
end

function Client:sock_close()
  self._sock:close()
  self._sock = nil
end

end

return function(...)
  return Client.new(...)
end
