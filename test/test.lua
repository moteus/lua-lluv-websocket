local uwebsocket = require "lluv.websocket"
local websocket  = require "websocket"
local bit        = require "lluv.websocket.bit"

assert(websocket.client.lluv)
assert(websocket.client.lluv.sync)
assert(websocket.server.lluv)

local ch = '\239'
local m  = 0x0F
local b  = string.byte(ch)
local v  = bit.bxor(b, m)
local a  = bit.band(v, 0xFF)
print("BYTE:", b)
print("MASK:", v)
print("AND :", a)
print("CAND:", string.char(a))
print("CMSK:", string.char(v))

uwebsocket.__self_test()
