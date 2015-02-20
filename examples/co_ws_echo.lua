local uv     = require "lluv"
local ut     = require "lluv.utils"
local socket = require "lluv.luasocket"
local WS     = require "websocket"

ut.corun(function()
  local cli = WS.client.lluv.sync{}
  print("Connect:", cli:connect("ws://echo.websocket.org", "echo"))
  while true do
    cli:send("hello")
    print("Message:", cli:receive())
    socket.sleep(1)
  end
end)

uv.run()

