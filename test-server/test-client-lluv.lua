local uv = require"lluv"
local WS = require"websocket.client_lluv"

local cli = WS() do

cli:on_open(function(ws)
  print("Connected")
end)

cli:on_error(function(ws, err)
  print("Error:", err)
end)

cli:on_message(function(ws, msg, code)
  if math.mod(tonumber(msg), 60) == 0 then
    print("Message:", msg)
  end
end)

cli:connect("ws://127.0.0.1:12345", "dumb-increment-protocol")

end

local cli = WS() do

local timer = uv.timer():start(0, 5000, function()
  cli:send("ECHO")
end):stop()

cli:on_open(function(ws)
  print("Connected")
  timer:again()
end)

cli:on_error(function(ws, err)
  print("Error:", err)
end)

cli:on_message(function(ws, msg, code)
  print("Message:", msg)
end)

cli:connect("ws://127.0.0.1:12345", "lws-mirror-protocol")

end

uv.run()


