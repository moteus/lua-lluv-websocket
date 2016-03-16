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
  -- "lua-websockets-core",
  "lluv > 0.1.1",
}

build = {
  type = "builtin",

  modules = {
    ['lluv.websocket']                = 'src/lluv/websocket.lua',
    ['lluv.websocket.utf8']           = 'src/lluv/websocket/utf8.lua',
    ['lluv.websocket.bit']            = 'src/lluv/websocket/bit.lua',
    ['lluv.websocket.tools']          = 'src/lluv/websocket/tools.lua',
    ['lluv.websocket.frame']          = 'src/lluv/websocket/frame.lua',
    ['lluv.websocket.error']          = 'src/lluv/websocket/error.lua',
    ['lluv.websocket.split']          = 'src/lluv/websocket/split.lua',
    ['lluv.websocket.handshake']      = 'src/lluv/websocket/handshake.lua',
    ['lluv.websocket.luasocket']      = 'src/lluv/websocket/luasocket.lua',
    ['lluv.websocket.extensions']     = 'src/lluv/websocket/extensions.lua',
    ['lluv.websocket.utf8_validator'] = 'src/lluv/websocket/utf8_validator.lua',

    ['lluv.websocket.extensions.permessage-deflate'] = 'src/lluv/websocket/extensions/permessage-deflate.lua',
  }
}
