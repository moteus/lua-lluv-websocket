pcall (require, "luacov")

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE
local equal, IT = utils.is_equal, utils.IT

local Deflate = require "lluv.websocket.extensions.permessage-deflate"
local ut      = require "lluv.utils"

local ENABLE = true

------------------------------------------------------------------
local _ENV = TEST_CASE'accept' if ENABLE then
local it = IT(_ENV or _M)

it('should make basic offer', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())
  assert(ext:accept{})
end)

it('should offer server max window', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.server_max_window_bits)

  assert(ext:accept{server_max_window_bits=10})

  assert_equal(10, ext._options.inflateWindow)
end)

it('should fail accept because unknown options', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())

  local _, err = assert_nil(ext:accept{foo=true})
  assert_not_nil(err)
end)

it('should fail accept because no server_max_window_bits', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.server_max_window_bits)

  local _, err = assert_nil(ext:accept{})
  assert_not_nil(err)
end)

it('should fail accept because server_max_window_bits to high', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.server_max_window_bits)

  local _, err = assert_nil(ext:accept{
    server_max_window_bits = 11
  })

  assert_not_nil(err)
end)

it('should accept lower server_max_window_bits', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.server_max_window_bits)

  assert(ext:accept{
    server_max_window_bits = 8
  })

  assert_equal(8, ext._options.inflateWindow)
end)

it('should accept any server_max_window_bits', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = true
  })
  local offer = assert_table(ext:offer())
  assert_true(offer.server_max_window_bits)

  assert(ext:accept{
    server_max_window_bits = 11
  })
end)

it('should accept default server_max_window_bits', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = 15
  })
  local offer = assert_table(ext:offer())
  assert_equal(15, offer.server_max_window_bits)

  assert(ext:accept{})
  assert_equal(15, ext._options.inflateWindow)
end)

it('should fail accept because server_max_window_bits equal true', function()
  local ext = assert(Deflate.client{
    server_max_window_bits = true
  })
  local offer = assert_table(ext:offer())
  assert_true(offer.server_max_window_bits)

  local _, err = assert_nil(ext:accept{
    server_max_window_bits = true
  })
  assert_not_nil(err)
end)

it('should accept without accept client_max_window_bits', function()
  local ext = assert(Deflate.client{
    client_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.client_max_window_bits)

  assert(ext:accept{})
  assert_equal(10, ext._options.deflateWindow)
end)

it('should fail accept because client_max_window_bits to high', function()
  local ext = assert(Deflate.client{
    client_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.client_max_window_bits)

  local _, err = assert_nil(ext:accept{
    client_max_window_bits = 11
  })

  assert_not_nil(err)
end)

it('should fail accept because client_max_window_bits equal true', function()
  local ext = assert(Deflate.client{
    client_max_window_bits = true
  })
  local offer = assert_table(ext:offer())
  assert_true(offer.client_max_window_bits)

  local _, err = assert_nil(ext:accept{
    client_max_window_bits = true
  })
  assert_not_nil(err)
end)

it('should accept lower client_max_window_bits', function()
  local ext = assert(Deflate.client{
    client_max_window_bits = 10
  })
  local offer = assert_table(ext:offer())
  assert_equal(10, offer.client_max_window_bits)

  assert(ext:accept{client_max_window_bits = 8})
  assert_equal(8, ext._options.deflateWindow)
end)

it('should fail accept without server_no_context_takeover', function()
  local ext = assert(Deflate.client{
    server_no_context_takeover = true
  })
  local offer = assert_table(ext:offer())
  assert_equal(true, offer.server_no_context_takeover)

  local _, err = assert_nil(ext:accept{})
  assert_not_nil(err)
end)

it('should accept server_no_context_takeover', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())
  assert_nil(offer.server_no_context_takeover)

  assert(ext:accept{
    server_no_context_takeover = true
  })

  assert_true(ext._options.inflateNoContext)
end)

it('should accept without client_no_context_takeover', function()
  local ext = assert(Deflate.client{
    client_no_context_takeover = true
  })
  local offer = assert_table(ext:offer())
  assert_equal(true, offer.client_no_context_takeover)

  assert(ext:accept{})

  assert_true(ext._options.deflateNoContext)
end)



end
------------------------------------------------------------------

------------------------------------------------------------------
local _ENV = TEST_CASE'response' if ENABLE then
local it = IT(_ENV or _M)

it('should basic response', function()
  local ext = assert(Deflate.server{})
  local response = assert_table(ext:response{})
end)

it('should resopnse with server_max_window_bits as true', function()
  local ext = assert(Deflate.server{})
  local response = assert_table(ext:response{
    server_max_window_bits = true;
  })
  assert_equal(15, response.server_max_window_bits)
end)

it('should resopnse with client_max_window_bits as true', function()
  local ext = assert(Deflate.server{})
  local response = assert_table(ext:response{
    client_max_window_bits = true;
  })
  assert_equal(15, response.client_max_window_bits)
end)

it('should resopnse with empty client_max_window_bits', function()
  local ext = assert(Deflate.server{})
  local response = assert_table(ext:response{})
  assert_nil(response.client_max_window_bits)
end)

it('should resopnse with empty server_max_window_bits', function()
  local ext = assert(Deflate.server{})
  local response = assert_table(ext:response{})
  assert_nil(response.server_max_window_bits)
end)

it('should not resopnse with server_max_window_bits to high', function()
  local ext = assert(Deflate.server{
    server_max_window_bits = 10
  })
  local _, err = assert_nil(ext:response{
    server_max_window_bits = 12
  })
  assert_nil(err)
end)

it('should resopnse with second variant of server_max_window_bits', function()
  local ext = assert(Deflate.server{
    server_max_window_bits = 10
  })

  local response = assert_table(ext:response{
    {server_max_window_bits = 12};
    {server_max_window_bits = 8};
  })

  assert_equal(8, ext._options.deflateWindow)
  assert_equal(8, response.server_max_window_bits)
end)

it('should not resopnse with client_max_window_bits to high', function()
  local ext = assert(Deflate.server{
    client_max_window_bits = 10
  })
  local _, err = assert_nil(ext:response{
    client_max_window_bits = 12
  })
  assert_nil(err)
end)

it('should resopnse with second variant of client_max_window_bits', function()
  local ext = assert(Deflate.server{
    client_max_window_bits = 10
  })

  local response = assert_table(ext:response{
    {client_max_window_bits = 12};
    {client_max_window_bits = 8};
  })

  assert_equal(8, ext._options.inflateWindow)
  assert_equal(8, response.client_max_window_bits)
end)

it('should not resopnse with disabled server_no_context_takeover', function()
  local ext = assert(Deflate.server{
    server_no_context_takeover = false
  })
  local _, err = assert_nil(ext:response{
    server_no_context_takeover = true
  })
  assert_nil(err)
end)

it('should not resopnse with disabled client_no_context_takeover', function()
  local ext = assert(Deflate.server{
    client_no_context_takeover = false
  })
  local _, err = assert_nil(ext:response{
    client_no_context_takeover = true
  })
  assert_nil(err)
end)

it('should resopnse with non standart server_max_window_bits', function()
  local ext = assert(Deflate.server{
    server_max_window_bits = 10
  })

  local response = assert_table(ext:response{})

  assert_equal(10, ext._options.deflateWindow)
  assert_equal(10, response.server_max_window_bits)
end)

it('should resopnse with non standart client_max_window_bits', function()
  local ext = assert(Deflate.server{
    client_max_window_bits = 10
  })

  local response = assert_table(ext:response{})

  assert_equal(10, ext._options.inflateWindow)
  assert_equal(10, response.client_max_window_bits)
end)
end
------------------------------------------------------------------

utils.RUN()