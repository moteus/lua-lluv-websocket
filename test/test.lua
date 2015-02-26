local uwebsocket = require "lluv.websocket"
local websocket  = require "websocket"

assert(websocket.client.lluv)
assert(websocket.client.lluv.sync)
assert(websocket.server.lluv)
