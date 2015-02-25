local frame     = require 'websocket.frame'
local uv        = require 'lluv'
local ut        = require 'lluv.utils'
local uws       = require 'lluv.websocket'

local ok, ssl   = pcall(require, 'lluv.ssl')
if not ok then ssl = nil end

local ocall     = function (f, ...) if f then return f(...) end end

local TEXT, BINARY = frame.TEXT, frame.BINARY

local Client = ut.class() do

local cleanup = function(self)
  if self._sock then self._sock:close() end
  self._sock = nil
end

local on_close = function(self, was_clean, code, reason)
  cleanup(self)
  ocall(self._on_close, self, was_clean, code, reason or '')
end

local on_error = function(self, err, dont_cleanup)
  if not dont_cleanup then cleanup(self) end

  ocall(self._on_error, self, err)
end

local on_open = function(self)
  self._state = 'OPEN'
  ocall(self._on_open, self)
end

local handle_socket_err = function(self, err)
  self._sock:close(function(self, clean, code, reason)
    on_error(self, err)
  end)
end

function Client:__init(ws)
  self._ws    = ws or {}

  self._on_send_done = function(sock, err)
    if err then handle_socket_err(self, err) end
  end

  return self
end

function Client:connect(url, proto)
  if self._sock then return end

  if url:match("^wss:") then
    if not self._ssl_ctx then
      local ctx = assert(self._ws.ssl)
      if type(ctx.client) == "function" then
        self._ssl_ctx = ctx
      else
        self._ssl_ctx = assert(ssl.context(ctx))
      end
    end
    self._sock = self._ssl_ctx:client()
  else
    self._sock = uv.tcp()
  end

  self._sock = uws.new(self._sock)

  self._sock:connect(url, proto, function(sock, err)
    if err then return on_error(self, err) end

    on_open(self)

    sock:start_read(function(sock, err, message, opcode)
      if err then
        if (err:name() == 'EOF') and (err:cat() == 'WEBSOCKET') then
          return self._sock:close(function(sock, clean, code, reason)
            on_close(self, clean, code, reason)
          end)
        end
        return handle_sock_err(self, err)
      end

      if opcode == TEXT or opcode == BINARY then
        return ocall(self._on_message, self, message, opcode)
      end
    end)
  end)

  return self
end

function Client:on_close(handler)
  self._on_close = handler
end

function Client:on_error(handler)
  self._on_error = handler
end

function Client:on_open(handler)
  self._on_open = handler
end

function Client:on_message(handler)
  self._on_message = handler
end

function Client:send(message, opcode)
  self._sock:write(message, opcode, self._on_send_done)
end

function Client:close(code, reason, timeout)
  self._sock:close(code, reason, function(sock, clean, code, reason)
    on_close(self, clean, code, reason)
  end)

  return self
end

end

return setmetatable({
  sync = require'websocket.client_lluv_sync';
},{__call = function(_, ...)
  return Client.new(...)
end})
