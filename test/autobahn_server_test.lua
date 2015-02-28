local uv  = require"lluv"
local ws  = require"lluv.websocket"

local server = ws.new{ssl = ctx}
server:bind("127.0.0.1", 9001, function(self, err)
  if err then
    print("Server error:", err)
    return server:close()
  end

  server:listen("echo", function(self, err)
    if err then
      print("Server listen:", err)
      return server:close()
    end

    local cli = server:accept()
    cli:handshake(function(self, err, protocol)
      if err then
        print("Server handshake error:", err)
        return cli:close()
      end
      print("New server connection:", protocol)

      cli:start_read(function(self, err, message, opcode)
        if err then
          print("Server read error:", err)
          return cli:close()
        end

        if opcode == ws.TEXT or opcode == ws.BINARY then
          cli:write(message, opcode)
        end
      end)
    end)
  end)
end)

uv.run()
