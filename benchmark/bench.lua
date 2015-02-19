local uv = require"lluv"
local ws = require"websocket"

local N = 1000
local dt
local msg = ('0'):rep(100)

local server = ws.server.lluv.listen{port = 12345,
  protocols = {
    ticks = function(ws)
      local n  = 0
      ws:on_message(function(ws, msg, code)
        n = n + 1
        if n == N then
          dt = uv.hrtime() - dt
          ws:send(tostring(dt))
        end
      end)
      dt = uv.hrtime()
    end
  }
}

local cli = ws.client.lluv() do

cli:on_open(function(ws)
  for i = 1, N do
    ws:send(msg)
  end
end)

cli:on_error(function(ws, err)
  print("Error:", err)
  server:close()
end)

cli:on_message(function(ws, msg)
  local dt = tonumber(msg)
  print("message", dt)
  
  print( string.format(
    "%d messages in %.2fs (%.0f/s)", N, dt / 1e9, N / (dt / 1e9)
  ))
  cli:close()
end)

cli:on_close(function(ws, ...)
  print("Close:", ...)
  server:close()
end)

cli:connect("ws://127.0.0.1:12345", "ticks")

end

uv.run()


