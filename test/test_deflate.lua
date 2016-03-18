pcall (require, "luacov")

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE
local equal, IT = utils.is_equal, utils.IT

local table   = table

local Deflate = require "lluv.websocket.extensions.permessage-deflate"
local ut      = require "lluv.utils"

local TEXT = 1

local function hex2bin(str)
  local s = ''
  string.gsub(str, "(%x%x)", function(c)
    s = s .. string.char(tonumber(c, 16))
  end)
  return s
end

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

it('should fail accept with invalid server_max_window_bits', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())

  local _, err = assert_nil(ext:accept{
    server_max_window_bits = 'hello';
  })
  assert_not_nil(err)
end)

it('should fail accept with invalid client_max_window_bits', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())

  local _, err = assert_nil(ext:accept{
    client_max_window_bits = 'hello';
  })
  assert_not_nil(err)
end)

it('should fail accept with invalid client_no_context_takeover', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())

  local _, err = assert_nil(ext:accept{
    client_no_context_takeover = 1;
  })
  assert_not_nil(err)
end)

it('should fail accept with invalid server_no_context_takeover', function()
  local ext = assert(Deflate.client{})
  local offer = assert_table(ext:offer())

  local _, err = assert_nil(ext:accept{
    client_no_context_takeover = 1;
  })
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

it('should fail resopnse with invalid server_max_window_bits', function()
  local ext = assert(Deflate.server{})
  local _, err = assert_nil(ext:response{
    server_max_window_bits = 'hello';
  })
  assert_not_nil(err)
end)

it('should fail resopnse with invalid client_max_window_bits', function()
  local ext = assert(Deflate.server{})
  local _, err = assert_nil(ext:response{
    client_max_window_bits = 'hello';
  })
  assert_not_nil(err)
end)

it('should fail resopnse with invalid client_no_context_takeover', function()
  local ext = assert(Deflate.server{})
  local _, err = assert_nil(ext:response{
    client_no_context_takeover = 1;
  })
  assert_not_nil(err)
end)

it('should fail resopnse with invalid server_no_context_takeover', function()
  local ext = assert(Deflate.server{})
  local _, err = assert_nil(ext:response{
    client_no_context_takeover = 1;
  })
  assert_not_nil(err)
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

------------------------------------------------------------------
local _ENV = TEST_CASE'encode/decode' if ENABLE then
local it = IT(_ENV or _M)

local AutoBahnEncoded = {
  hex2bin'd4 98 41 6b c2 30 1c c5 ef 83 7d 87 d2 b3 74 c9 bf 69 1a 77 1b 1e 77 d8 be 81 d4 d9 a1 c3 19 a9',
  hex2bin'75 30 64 df 7d 49 d9 60 8a be c9 d8 3b 04 f1 d2 b4 da 1f 49 df 2f 7d fb eb ab 2c cb f2 bb 5d ef',
  hex2bin'67 cd 62 fd f8 de 2f fc fa 46 15 b6 50 f9 6d b6 1f 46 e3 09 ba 08 9f 9f 47 e2 c1 59 bb 68 de 96',
  hex2bin'be 0b c7 f3 87 fb 7c 74 6a 6c b2 f2 db f6 d4 09 f3 5d d7 f4 4b bf 0e 63 72 30 d0 b5 af be 6f 87',
  hex2bin'eb 26 7e 1e af d5 4a a9 a3 53 36 be eb 9f 97 ab e1 97 9b af 9b df 0c 37 3f 55 53 1b be 4f cd b6',
  hex2bin'9d ea f8 29 5e b6 e1 5f be 2f ff 18 1d 30 49 92 4c 02 99 ca 24 99 4a c8 64 92 64 32 90 a9 4a 92',
  hex2bin'a9 82 4c 96 c6 54 55 4c 2a 0b a9 6a 16 95 16 2a 55 0d a9 1c 8d ca 58 26 95 03 54 92 a4 a5 04 5a',
  hex2bin'4a 92 b4 94 40 4b 49 92 96 12 68 29 49 d2 52 02 2d 25 49 5a 4a a0 a5 84 67 29 6d 6a 26 15 b2 94',
}

local AutoBahnDecoded = {
  hex2bin'7b 0d 0a 20 20 20 22 41 75 74 6f 62 61 68 6e 50 79 74 68 6f 6e 2f 30 2e 36 2e 30 22 3a 20 7b 0d',
  hex2bin'0a 20 20 20 20 20 20 22 31 2e 31 2e 31 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68',
  hex2bin'61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f',
  hex2bin'72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69',
  hex2bin'6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f',
  hex2bin'64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65',
  hex2bin'22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f',
  hex2bin'31 5f 31 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 31 2e',
  hex2bin'32 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22',
  hex2bin'2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b',
  hex2bin'22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20',
  hex2bin'20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a',
  hex2bin'20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e',
  hex2bin'70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 31 5f 32 2e 6a 73 6f 6e 22 0d 0a 20',
  hex2bin'20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 31 2e 33 22 3a 20 7b 0d 0a 20 20 20 20 20',
  hex2bin'20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20',
  hex2bin'22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20',
  hex2bin'20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74',
  hex2bin'65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65',
  hex2bin'70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30',
  hex2bin'5f 63 61 73 65 5f 31 5f 31 5f 33 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20',
  hex2bin'20 20 20 22 31 2e 31 2e 34 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f',
  hex2bin'72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f',
  hex2bin'73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a',
  hex2bin'20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a',
  hex2bin'20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22',
  hex2bin'61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 31 5f 34 2e',
  hex2bin'6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 31 2e 35 22 3a 20',
  hex2bin'7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20',
  hex2bin'20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a',
  hex2bin'20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20',
  hex2bin'20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20',
  hex2bin'20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68',
  hex2bin'6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 31 5f 35 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20',
  hex2bin'20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 31 2e 36 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20',
  hex2bin'22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68',
  hex2bin'61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75',
  hex2bin'72 61 74 69 6f 6e 22 3a 20 32 35 35 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43',
  hex2bin'6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f',
  hex2bin'72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63',
  hex2bin'61 73 65 5f 31 5f 31 5f 36 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20',
  hex2bin'20 22 31 2e 31 2e 37 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22',
  hex2bin'3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65',
  hex2bin'22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 31',
  hex2bin'32 35 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a',
  hex2bin'20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22',
  hex2bin'61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 31 5f 37 2e',
  hex2bin'6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 31 2e 38 22 3a 20',
  hex2bin'7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20',
  hex2bin'20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a',
  hex2bin'20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 31 34 36 2c 0d 0a 20 20 20 20 20',
  hex2bin'20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20',
  hex2bin'20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79',
  hex2bin'74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 31 5f 38 2e 6a 73 6f 6e 22 0d 0a 20 20 20',
  hex2bin'20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 32 2e 31 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20',
  hex2bin'20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62',
  hex2bin'65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22',
  hex2bin'64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43',
  hex2bin'6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f',
  hex2bin'72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63',
  hex2bin'61 73 65 5f 31 5f 32 5f 31 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20',
  hex2bin'20 22 31 2e 32 2e 32 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22',
  hex2bin'3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65',
  hex2bin'22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32',
  hex2bin'2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31',
  hex2bin'30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75',
  hex2bin'74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 32 5f 32 2e 6a 73',
  hex2bin'6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 32 2e 33 22 3a 20 7b 0d',
  hex2bin'0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20',
  hex2bin'20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20',
  hex2bin'20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20',
  hex2bin'22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20',
  hex2bin'20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e',
  hex2bin'5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 32 5f 33 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d',
  hex2bin'2c 0d 0a 20 20 20 20 20 20 22 31 2e 32 2e 34 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62',
  hex2bin'65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76',
  hex2bin'69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61',
  hex2bin'74 69 6f 6e 22 3a 20 32 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65',
  hex2bin'43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69',
  hex2bin'6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f',
  hex2bin'31 5f 32 5f 34 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e',
  hex2bin'32 2e 35 22 3a 20 7b 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f',
  hex2bin'4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22',
  hex2bin'4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 32 2c 0d 0a 20',
  hex2bin'20 20 20 20 20 20 20 20 22 72 65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c',
  hex2bin'0d 0a 20 20 20 20 20 20 20 20 20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61',
  hex2bin'68 6e 70 79 74 68 6f 6e 5f 30 5f 36 5f 30 5f 63 61 73 65 5f 31 5f 32 5f 35 2e 6a 73 6f 6e 22 0d',
  hex2bin'0a 20 20 20 20 20 20 7d 2c 0d 0a 20 20 20 20 20 20 22 31 2e 32 2e 36 22 3a 20 7b 0d 0a 20 20 20',
  hex2bin'20 20 20 20 20 20 22 62 65 68 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20 20',
  hex2bin'20 20 22 62 65 68 61 76 69 6f 72 43 6c 6f 73 65 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20',
  hex2bin'20 20 20 22 64 75 72 61 74 69 6f 6e 22 3a 20 31 34 37 2c 0d 0a 20 20 20 20 20 20 20 20 20 22 72',
  hex2bin'65 6d 6f 74 65 43 6c 6f 73 65 43 6f 64 65 22 3a 20 31 30 30 30 2c 0d 0a 20 20 20 20 20 20 20 20',
  hex2bin'20 22 72 65 70 6f 72 74 66 69 6c 65 22 3a 20 22 61 75 74 6f 62 61 68 6e 70 79 74 68 6f 6e 5f 30',
  hex2bin'5f 36 5f 30 5f 63 61 73 65 5f 31 5f 32 5f 36 2e 6a 73 6f 6e 22 0d 0a 20 20 20 20 20 20 7d 2c 0d',
  hex2bin'0a 20 20 20 20 20 20 22 31 2e 32 61 76 69 6f 72 22 3a 20 22 4f 4b 22 2c 0d 0a 20 20 20 20 20 20',
  hex2bin'20 20 20 22 62 65 6f'
}

local function make_pair(cli, srv)
  local client   = assert(Deflate.client(cli))
  local server   = assert(Deflate.server(srv))
  local offer    = assert_table(client:offer())
  local response = assert_table(server:response(offer))
  assert(client:accept(response))

  return server, client
end

it('should basic encode', function()
  local server, client = make_pair()
  local message = ('hello'):rep(10)
  local encoded = assert_string(server:encode(TEXT, message, true))
  assert_not_equal(message, encoded)
  local decoded = assert_string(client:decode(TEXT, encoded, true))
  assert_equal(message, decoded)
  assert_not_nil(server._deflate)
  assert_not_nil(client._inflate)
end)

it('should correct inflate', function()
  local encoded = table.concat(AutoBahnEncoded)
  local decoded = table.concat(AutoBahnDecoded)
  local server = assert(Deflate.server())
  assert_table(server:response{})
  assert_equal(decoded, server:decode(TEXT, encoded, true))
end)

it('should correct inflate by chunks', function()
  local decoded = table.concat(AutoBahnDecoded)
  local chunks = {}
  local server = assert(Deflate.server())
  assert_table(server:response{})

  for i = 1, #AutoBahnEncoded do
    local encoded = AutoBahnEncoded[i]
    local fin     = i == #AutoBahnEncoded
    local chunk, err = server:decode(TEXT, encoded, fin)
    assert_nil(err)
    chunks[#chunks + 1] = chunk
  end

  assert_equal(decoded, table.concat(chunks))
end)

it('should basic encode no context', function()
  local server, client = make_pair(
    {client_no_context_takeover = true},
    {server_no_context_takeover = true}
  )
  local message = ('hello'):rep(10)
  local encoded = assert_string(server:encode(TEXT, message, true))
  assert_not_equal(message, encoded)
  local decoded = assert_string(client:decode(TEXT, encoded, true))
  assert_equal(message, decoded)
  assert_nil(server._deflate)
  assert_nil(client._inflate)
end)

it('should encode by chunks without context', function()
  local server, client = make_pair(
    {client_no_context_takeover = true},
    {server_no_context_takeover = true}
  )

  for i = 1, 2 do
    local encoded = {}
    for i = 1, #AutoBahnDecoded do
      local fin        = i == #AutoBahnDecoded
      local chunk, err = server:encode(TEXT, AutoBahnDecoded[i], fin)
      assert_nil(err)
      encoded[#encoded + 1] = chunk
    end

    local decoded = {}
    for i = 1, #encoded do
      local fin        = i == #encoded
      local chunk, err = client:decode(TEXT, encoded[i], fin)
      assert_nil(err)
      decoded[#decoded + 1] = chunk
    end

    assert_equal(table.concat(AutoBahnDecoded), table.concat(decoded))
  end
end)

it('should encode by chunks', function()
  local server, client = make_pair()

  for i = 1, 2 do
    local encoded = {}
    for i = 1, #AutoBahnDecoded do
      local fin        = i == #AutoBahnDecoded
      local chunk, err = server:encode(TEXT, AutoBahnDecoded[i], fin)
      assert_nil(err)
      encoded[#encoded + 1] = chunk
    end

    local decoded = {}
    for i = 1, #encoded do
      local fin        = i == #encoded
      local chunk, err = client:decode(TEXT, encoded[i], fin)
      assert_nil(err)
      decoded[#decoded + 1] = chunk
    end

    assert_equal(table.concat(AutoBahnDecoded), table.concat(decoded))
  end
end)

end
------------------------------------------------------------------

utils.RUN()