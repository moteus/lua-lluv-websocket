# lluv-websocket

This library includes stream interface for lluv and lluv backend for lua-websockets

```Lua
local cli = ws.new()

cli:connect("ws://echo.websocket.org", "echo", function(self, err)
  if err then
    print("Client connect error:", err)
    return cli:close()
  end

  local counter = 0
  cli:start_read(function(self, err, message, opcode)
    if err then
      print("Client read error:", err)
      return cli:close()
    end

    print("Client recv:", message)

    if counter > 10 then
      cli:close(function(self, ...)
        print("Client close:", ...)
      end)
    end

    counter = counter + 1
    cli:write("Echo #" .. counter)
  end)

  cli:write("Echo #0")
end)

uv.run()
```
