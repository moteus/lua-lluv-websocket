local uv        = require "lluv"
local websocket = require "websocket"

require "websocket.server_lluv".listen{
  protocols = {
    ['lws-mirror-protocol'] = function(ws)
      ws:on_message(
        function(ws,data,opcode)
          if opcode == websocket.TEXT then
            ws:broadcast(data)
          end
        end)
    end,
    ['dumb-increment-protocol'] = function(ws)
      local number = 0
      local timer = uv.timer():start(100, 100, function()
        ws:send(tostring(number))
        number = number + 1
      end)

      ws:on_message(function(ws, message, opcode)
        if opcode == websocket.TEXT then
          if message:match('reset') then
            number = 0
          end
        end
      end)

      ws:on_close(function()
        timer:close()
      end)
    end
  },
  port = 12345
}

local function cur_dir()
  if package.config:sub(1, 1) == '\\' then
    local f = io.popen('cd')
    return '/' .. f:read("*all"):gsub("\\", "/"):gsub("\n", "")
  end
  local f = io.popen('pwd')
  if f then return f:read("*all") end
end

print('Open browser:')
print('file://'.. cur_dir() ..'/index.html')

uv.run()
