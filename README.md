# lluv-websocket
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv-websocket.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv-websocket)
[![Coverage Status](https://coveralls.io/repos/moteus/lua-lluv-websocket/badge.svg?branch=master)](https://coveralls.io/r/moteus/lua-lluv-websocket?branch=master)

This library includes stream interface for lluv and lluv backend for [lua-websockets](https://github.com/lipp/lua-websockets)

## lluv status
 * PING/PONG - done
 * WSS supports - done
 * UT8 validate - done (except some fast fail cases)
 * Validate RSV bits - needs [lua-websockets/PR #55](https://github.com/lipp/lua-websockets/pull/55) (tested)
 * IPv6 - needs [lua-websockets/PR #56](https://github.com/lipp/lua-websockets/pull/56) (not tested)
 * Extension (e.g. compression) - not supported (for now I have no plans for this)

## [lua-websockets](https://github.com/lipp/lua-websockets) backend status
 * Async server - done (not tested)
 * Async client - done (not tested)
 * Sync client - done (not tested / use `websocket.sync` implementation not `lluv.wobsocket` one)

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
