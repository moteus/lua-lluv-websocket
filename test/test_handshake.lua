pcall (require, "luacov")

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE
local equal, IT = utils.is_equal, utils.IT

local handshake = require "lluv.websocket.handshake"

local table, tostring = table, tostring

local function H(t)
  return table.concat(t, '\r\n') .. '\r\n\r\n'
end

local ENABLE = true

------------------------------------------------------------------
local _ENV = TEST_CASE'accept upgrade' if ENABLE then
local it = IT(_ENV or _M)

it('should decode headers',function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade:   websocket ',
    'Connection:  keep-alive, Upgrade ',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: chat, superchat   ',
    'Sec-WebSocket-Protocol: foo  ',
    'Sec-WebSocket-Version: 13',
  }
  local h = assert_table(handshake.http_headers(request))
  assert_equal('websocket',                h['upgrade'                ])
  assert_equal('server.example.com',       h['host'                   ])
  assert_equal('keep-alive, upgrade',      h['connection'             ])
  assert_equal('dGhlIHNhbXBsZSBub25jZQ==', h['sec-websocket-key'      ])
  assert_equal('chat, superchat, foo',     h['sec-websocket-protocol' ])
end)

it('should accept basic request', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: chat, superchat',
    'Sec-WebSocket-Version: 13',
  }

  local h, protocol = assert_table(handshake.accept_upgrade(request, {'chat'}))
  assert_equal('chat', protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_match('Sec%-WebSocket%-Protocol:%s*chat%s-\r\n', response)
end)

it('should accept quoted version', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: chat, superchat',
    'Sec-WebSocket-Version: "13"',
  }

  local h, protocol = assert_table(handshake.accept_upgrade(request, {'chat'}))
  assert_equal('chat', protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_match('Sec%-WebSocket%-Protocol:%s*chat%s-\r\n', response)
end)

it('should accept quoted protocol', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: "chat proto", "superchat"',
    'Sec-WebSocket-Version: "13"',
  }

  local h, protocol = assert_table(handshake.accept_upgrade(request, {'chat proto'}))
  assert_equal('chat proto', protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_match('Sec%-WebSocket%-Protocol:%s*"chat proto"%s-\r\n', response)
end)

it('should accept with multiple values in connection', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: keep-alive, Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: chat, superchat',
    'Sec-WebSocket-Version: 13',
  }

  local h, protocol = assert_table(handshake.accept_upgrade(request, {'chat'}))
  assert_equal('chat', protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_match('Sec%-WebSocket%-Protocol:%s*chat%s-\r\n', response)
end)

it('should accept without protocol', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: keep-alive, Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Version: 13',
  }

  local h, protocol = assert_table(handshake.accept_upgrade(request, {'chat'}))
  assert_nil(protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_not_match('Sec%-WebSocket%-Protocol:', response)
end)

it('should fail without upgrade', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: keep-alive',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Version: 13',
  }

  local _, response = assert_nil(handshake.accept_upgrade(request, {'chat proto'}))
  assert_match("HTTP/1%.1%s+4", response)
end)

it('should fail without upgrade-websocket', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: "chat proto", "superchat"',
    'Sec-WebSocket-Version: 13',
  }

  local _, response = assert_nil(handshake.accept_upgrade(request, {'chat proto'}))
  assert_match("HTTP/1%.1%s+4", response)
end)

it('should fail unsupported version', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Version: 25',
  }

  local _, response = assert_nil(handshake.accept_upgrade(request, {'chat proto'}))
  assert_match("HTTP/1%.1%s+4", response)
  assert_match('Sec%-WebSocket%-Version:.-13', response)
end)

it('should fail without version', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
  }

  local _, response = assert_nil(handshake.accept_upgrade(request, {'chat proto'}))
  assert_match("HTTP/1%.1%s+4", response)
end)

it('should fail without key', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Version: 16',
  }

  local _, response = assert_nil(handshake.accept_upgrade(request, {'chat proto'}))
  assert_match("HTTP/1%.1%s+4", response)
end)

it('should accept return extensions header', function()
  local request = H{
    'GET /chat HTTP/1.1',
    'Host:server.example.com',
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Protocol: chat, superchat',
    'Sec-WebSocket-Version: 13',
    'Sec-WebSocket-Extensions: permessage-foo',
    'Sec-WebSocket-Extensions: permessage-bar; bar=10',
    'Sec-WebSocket-Extensions: permessage-baz',
  }

  local h, protocol, extensions = assert_table(handshake.accept_upgrade(request, {'chat'}))
  assert_equal('chat', protocol)
  assert_match("HTTP/1%.1%s+101", h[1])
  local response = table.concat(h, '\r\n') .. '\r\n'
  assert_match('Sec%-WebSocket%-Accept:%s*s3pPLMBiTxaQ9kYGzzhZRbK%+xOo=%s-\r\n', response)
  assert_match('Sec%-WebSocket%-Protocol:%s*chat%s-\r\n', response)
  assert_equal("permessage-foo, permessage-bar; bar=10, permessage-baz", extensions)
end)

end
------------------------------------------------------------------

------------------------------------------------------------------
local _ENV = TEST_CASE'upgrade response' if ENABLE then
local it = IT(_ENV or _M)

local key = "AgjEEQO2Z2wHD84fAhMkJg=="

it('should make basic upgrade', function()
  local req = assert_string(handshake.upgrade_request{
    key        = key,
    host       = '127.0.0.1',
    port       = 80,
    protocols  = {},
    origin     = '',
    uri        = '/',
    extensions = '',
  })
  assert_match("GET[^\r\n]-HTTP/1%.1", req)
  assert_not_match("Sec%-WebSocket%-Extensions:", req)
  assert_not_match("Sec%-WebSocket%-Protocol:", req)
end)

it('should make upgrade with protocol', function()
  local req = assert_string(handshake.upgrade_request{
    key        = key,
    host       = '127.0.0.1',
    port       = 80,
    protocols  = {'chat', 'super chat'},
    origin     = '',
    uri        = '/',
    extensions = '',
  })
  assert_match("GET[^\r\n]-HTTP/1%.1", req)
  assert_not_match("Sec%-WebSocket%-Extensions:", req)
  assert_match("Sec%-WebSocket%-Protocol:", req)
  assert_match("Sec%-WebSocket%-Protocol:[^\r\n]-chat,", req)
  assert_match('Sec%-WebSocket%-Protocol:[^\r\n]-"super chat"', req)
end)

it('should make upgrade with extensions', function()
  local req = assert_string(handshake.upgrade_request{
    key        = key,
    host       = '127.0.0.1',
    port       = 80,
    protocols  = {},
    origin     = '',
    uri        = '/',
    extensions = 'permessage-foo',
  })
  assert_match("GET[^\r\n]-HTTP/1%.1", req)
  assert_not_match("Sec%-WebSocket%-Protocol:", req)
  assert_match("Sec%-WebSocket%-Extensions:", req)
  assert_match("Sec%-WebSocket%-Extensions: permessage%-foo", req)
end)

it('should make upgrade with non standart port', function()
  local req = assert_string(handshake.upgrade_request{
    key        = key,
    host       = '127.0.0.1',
    port       = 8024,
    protocols  = {},
    origin     = '',
    uri        = '/',
    extensions = '',
  })
  assert_match("GET[^\r\n]-HTTP/1%.1", req)
  assert_match("Host: 127.0.0.1:8024", req)
end)

end
------------------------------------------------------------------

utils.RUN()