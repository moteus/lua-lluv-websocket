package = "lluv-websocket"
version = "scm-0"

source = {
  url = "git://github.com/moteus/lua-lluv-websocket.git",
}

description = {
  summary = "Websockets for Lua based on libuv binding",
  homepage = "http://github.com/moteus/lua-lluv-websocket",
  license = "MIT/X11",
  detailed = "Provides async client and server for lluv."
}

dependencies = {
  "lua >= 5.1, < 5.4",
  "lua-websockets-core",
  "lluv > 0.1.1",
}

build = {
  type = "builtin",

  modules = {
    ['lluv.websocket']                = 'src/lluv/websocket.lua',
    ['lluv.websocket.utf8']           = 'src/lluv/websocket/utf8.lua',
    ['lluv.websocket.utf8_validator'] = 'src/lluv/websocket/utf8_validator.lua',
  }
}
