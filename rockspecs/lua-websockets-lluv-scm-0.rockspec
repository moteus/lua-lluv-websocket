package = "lua-websockets-lluv"
version = "scm-0"

source = {
  url = "git://github.com/moteus/lua-lluv-websocket.git",
}

description = {
  summary = "libuv backend for websockets for Lua",
  homepage = "http://github.com/moteus/lua-lluv-websocket",
  license = "MIT/X11",
  detailed = "Provides async client and server for lluv."
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "lua-websockets-core",
  "lluv-websocket",
}

build = {
  type = "builtin",

  modules = {
    ['websocket.server_lluv'     ] = 'src/websocket/server_lluv.lua',
    ['websocket.client_lluv'     ] = 'src/websocket/client_lluv.lua',
    ['websocket.client_lluv_sync'] = 'src/websocket/client_lluv_sync.lua',
  }
}
