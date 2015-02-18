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
local ocall     = function (f, ...) if f then return f(...) end end

local TEXT, BINARY, CLOSE = frame.TEXT, frame.BINARY, frame.CLOSE

local Client = ut.class() do

local cleanup = function(self)
  if self._close_timer then self._close_timer:close() end
  if self._sock then self._sock:close() end
  self._close_timer, self._sock = nil
end

local on_close = function(self, was_clean, code, reason)
  self._state = 'CLOSED'
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
  if self._state == 'OPEN' then
    on_close(self, false, 1006, err)
  elseif self._state ~= 'CLOSED' then
    on_error(self, err)
  end
end

local on_message = function(self, message, opcode)
  if opcode == TEXT or opcode == BINARY then
    return ocall(self._on_message, self, message, opcode)
  end

  if opcode == CLOSE then
    if self._state == 'CLOSING' then
      return on_close(self, true, 1005, '')
    end

    self._state = 'CLOSING'
    local code, reason = frame.decode_close(message)
    local encoded = frame.encode_close(code)
    encoded = frame.encode(encoded, CLOSE, true)
    self._sock:write(encoded, function(sock, err)
      if err then return handle_socket_err(self, err) end
      on_close(self, true, code or 1005, reason)
    end)
  end
end

function Client:__init(ws)
  self._state = 'CLOSED'
  self._ws    = ws or {}

  self._on_send_done = function(sock, err)
    if err then handle_socket_err(self, err) end
  end

  return self
end

function Client:connect(url, proto)
  if self._sock then return end

  if self._state ~= 'CLOSED' then
    return on_error(self, 'wrong state', true)
  end

  local protocol, host, port, uri = tools.parse_url(url)
  if protocol ~= 'ws' and protocol ~= 'wss'  then
    return on_error(self, 'bad protocol - ' .. protocol)
  end

  if protocol == 'wss' and not ssl then
    return on_error(self, 'unsuported protocol - ' .. protocol)
  end

  if port == '' then port = nil end
  if protocol == 'wss' then port = port or 443
  else port = port or 80 end

  self._state = 'CONNECTING'

  local key, req

  uv.getaddrinfo(host, port, {
    family   = "inet";
    socktype = "stream";
    protocol = "tcp";
  }, function(_, err, res)
    if err then
      self._state = 'CLOSED'
      return on_error(self, err)
    end
    
    local addr = res[1]
    if not addr then
      self._state = 'CLOSED'
      return on_error(self, "can not resolve: " .. host)
    end

    if protocol == 'wss' then
      self._ssl_ctx = self._ssl_ctx or assert(ssl.context(self._ws.ssl))
      self._sock = self._ssl_ctx:client()
    else
      self._sock = uv.tcp()
    end

    self._sock:connect(addr.address, port, function(sock, err)
      if self._state ~= 'CONNECTING' then return end

      if err then
        self._state = 'CLOSED'
        return on_error(self, err)
      end

      sock:write(req, function(sock, err)
        if self._state ~= 'CONNECTING' then return end

        if err then
          self._state = 'CLOSED'
          return on_error(self, err)
        end

        local buffer = ut.Buffer.new('\r\n\r\n')
        sock:start_read(function(sock, err, data)
          if self._state ~= 'CONNECTING' then return end

          if err then
            self._state = 'CLOSED'
            return on_error(self, err)
          end

          buffer:append(data)
          local response = buffer:read("*l")
          if not response then return end
          sock:stop_read()

          local headers = handshake.http_headers(response .. '\r\n\r\n')
          local expected_accept = handshake.sec_websocket_accept(key)
          if headers['sec-websocket-accept'] ~= expected_accept then
            self._state = 'CLOSED'
            return on_error(self, 'accept failed')
          end

          on_open(self)

          do -- start client loop
            local last = buffer:read("*a")
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

            sock:start_read(function(sock, err, data)
              if err then return handle_socket_err(self, err) end
              on_data(self, data)
            end)

            -- if we have some data from handshake
            if last then uv.defer(on_data, self, '') end
          end

        end)
      end)
    end)
  end)

  key = tools.generate_key()
  req = handshake.upgrade_request {
    key       = key,
    host      = host,
    port      = port,
    protocols = {proto or ''},
    origin    = self._ws.origin,
    uri       = uri
  }

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
  local encoded = frame.encode(message,opcode or frame.TEXT,true)
  self._sock:write(encoded, self._on_send_done)
end

function Client:close(code, reason, timeout)
  if self._state == 'CONNECTING' then
    self._state = 'CLOSING'
    return on_close(self, false, 1006, '')
  end

  if self._state == 'OPEN' then
    self._state = 'CLOSING'
    timeout = (timeout or 3) * 1000

    local encoded = frame.encode_close(code or 1000, reason)
    encoded = frame.encode(encoded, CLOSE, true)
    self._sock:write(encoded)

    self._close_timer = uv.timer(timeout, function()
      on_close(false, 1006, 'timeout')
    end):start()
  end
end

end

return function(...)
  return Client.new(...)
end
