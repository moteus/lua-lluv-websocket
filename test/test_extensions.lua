pcall (require, "luacov")

local utils     = require "utils"
local TEST_CASE = require "lunit".TEST_CASE
local equal, IT = utils.is_equal, utils.IT

local Extensions = require "lluv.websocket.extensions"
local handshake  = require "lluv.websocket.handshake"
local ut         = require "lluv.utils"

local tostring   = tostring

local decode_header_lpeg   = handshake._decode_header_lpeg
local decode_header_native = handshake._decode_header_native 
local decode_header        = decode_header_lpeg or decode_header_native
local encode_header        = handshake.encode_header
local H                    = encode_header

local D = function(s, ...)
  if type(s) == 'string' then
    return decode_header(s), ...
  end
  return t, ...
end

local function E(t)
  t.name = t[1]
  t.rsv1 = not not t[2]
  t.rsv2 = not not t[3]
  t.rsv3 = not not t[4]

  if not t.client then t.client = function() return t end end

  if not t.server then t.server = function() return t end end

  if type(t.offer) == 'table' then
    local offer = t.offer
    t.offer = function() return offer end
  elseif t.offer == false then
    t.offer = function() return end
  elseif t.offer == nil or t.offer == true then
    t.offer = function() return {} end
  end

  if type(t.accept) == 'boolean' then
    local accept = t.accept
    t.accept = function() return accept end
  elseif type(t.accept) == 'table' then
    local accept = t.accept
    t.accept = function() return (unpack or table.unpack)(accept, 1, 2) end
  elseif t.accept == nil then
    t.accept = function() return true end
  end

  if type(t.response) == 'table' then
    local response = t.response
    t.response = function() return response end
  elseif t.response == nil then
    t.response = function(self, params)
      return params[1]
    end
  elseif t.response == false then
    t.response = function() return end
  elseif type(t.response) == 'string' then
    local response = t.response
    t.response = function() return nil, response end
  end

  return t
end

local ENABLE = true

------------------------------------------------------------------
local _ENV = TEST_CASE'encode/decode header' if ENABLE then
local it = IT(_ENV or _M)

local function decode_header_test(decode_header)
  local name = decode_header == decode_header_lpeg and 'lpeg' or 'native'

  local test = function(pat, res)
    it('decode - ' .. name .. '/' .. (pat or '<NIL>'), function()
      local v = decode_header(pat)
      assert(equal(res, v))
    end)
  end

  test()
  test('', {})
  test('a', {
    {'a',{}};
  })
  test('a,b',{
    {'a',{}};
    {'b',{}};
  })
  test('a,a', {
    {'a',{}};
    {'a',{}};
  })
  test('a;b',{
    {'a',{b=true}};
  })
  test('a;b=1',{
    {'a',{b='1'}};
  })
  test('a; b; c=1; d=hi',{
    {'a',{
      b=true;
      c='1';
      d='hi'
      }
    };
  })
  test('a; b; c=1; b=hi',{
    {'a',{
      b={true, 'hi'};
      c='1';
      }
    };
  })
  test('a; b; c=1; d="hi"',{
    {'a',{b=true;c='1';d='hi'}};
  })
  test('a; b=1, c, b; d, c; e="hi there"; e, a; b',{
    {'a', {b='1'}};
    {'c', {}};
    {'b', {d=true}};
    {'c', {e={'hi there', true}}};
    {'a', {b=true}};
  })

  if decode_header == decode_header_lpeg then
    test('a; b=1, c, b; d, c; e="hi, there"; e, a; b',{
      {'a', {b='1'}};
      {'c', {}};
      {'b', {d=true}};
      {'c', {e={'hi, there', true}}};
      {'a', {b=true}};
    })
    test('a; b="hi, \\"there"', {
      {'a', {b = 'hi, "there'}};
    })
  end
end

local function encode_header_test()
  local test = function(pat)
    it('encode/' .. (pat or '<NIL>'), function()
      local res = decode_header(pat)
      local v = decode_header(encode_header(res))
      assert(equal(res, v))
    end)
  end

  test()
  test('')
  test('a')
  test('a,b')
  test('a,a')
  test('a;b')
  test('a;b=1')
  test('a; b; c=1; d=hi')
  test('a; b; c=1; b=hi')
  test('a; b; c=1; d="hi"')
  test('a; b=1, c, b; d, c; e="hi there"; e, a; b')

  if decode_header == decode_header_lpeg then
    test('a; b=1, c, b; d, c; e="hi, there"; e, a; b')
    test('a; b="hi, \\"there"')
  end

end

if decode_header_lpeg then
  decode_header_test(decode_header_lpeg)
end

decode_header_test(decode_header_native)

encode_header_test()

end
------------------------------------------------------------------

------------------------------------------------------------------
local _ENV = TEST_CASE'Extensions client' if ENABLE then
local it = IT(_ENV or _M)

local ext

function setup()
  ext = assert(Extensions.new())
end

function teardown()
  ext = nil
end

function test_accept()
  local offer = assert_table(D(ext:offer()))
  assert_equal(0, #offer)
  local ok, err = assert_nil(ext:accept(H{{'permessage-deflate'}}))
end

function test_offer()
  assert(ext:reg(E{'permessage-foo', true, false, false,
    offer  = function() return {value = true} end
  }))
  local offer = assert_table(D(ext:offer()))
  assert_equal(1, #offer)
  assert_equal('permessage-foo', offer[1][1])
  local params = assert_table(offer[1][2])
  assert_true(params.value)
end

function test_duplicate_ext_name()
  assert(ext:reg(E{'permessage-foo', true}))
  assert_nil(ext:reg(E{'permessage-foo', true}))
end

function test_duplicate_rsv_bit()
  assert(ext:reg(E{'permessage-foo', true,
    offer = {foo_param=true};
  }))
  assert(ext:reg(E{'permessage-bar', true,
    offer = {bar_param=true};
  }))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  assert(ext:accept(H{{'permessage-bar'}}))

  assert('permessage-bar', ext:accepted('permessage-bar'))
  assert_nil(ext:accepted('permessage-foo'))
end

function test_encode_decode()
  assert(ext:reg(E{'permessage-foo', true,
    offer = {foo_param=true};
    encode = function(self, opcode, msg, fin)
      return "permessage-foo/" .. msg 
    end;
    decode = function(self, opcode, msg, fin)
      assert_equal("permessage-foo/", msg:sub(1, 15))
      return msg:sub(16)
    end;
  }))

  assert(ext:reg(E{'permessage-bar', false, true,
    offer = {bar_param=true};
    encode = function(self, opcode, msg, fin)
      return "permessage-bar/" .. msg 
    end;
    decode = function(self, opcode, msg, fin)
      assert_equal("permessage-bar/", msg:sub(1, 15))
      return msg:sub(16)
    end;
  }))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  assert(ext:accept(H{{'permessage-bar'}, {'permessage-foo'}}))

  assert_equal('permessage-bar', ext:accepted('permessage-bar'))
  assert_equal('permessage-foo', ext:accepted('permessage-foo'))

  local text = 'HELLO'
  local msg, rsv1, rsv2, rsv3 = ext:encode(text, TEXT, true)
  assert_equal('permessage-foo/permessage-bar/HELLO', msg)
  assert_true(rsv1)
  assert_true(rsv2)
  assert_false(rsv3)

  local decode = ext:decode(msg, TEXT, true, rsv1, rsv2, rsv3)
  assert_equal(text, decode)

  msg, rsv1, rsv2, rsv3 = ext:encode(text, TEXT, true, {['permessage-foo'] = true})
  assert_equal('permessage-foo/HELLO', msg)
  assert_true(rsv1)
  assert_false(rsv2)
  assert_false(rsv3)

  decode = ext:decode(msg, TEXT, true, rsv1, rsv2, rsv3)
  assert_equal(text, decode)

  msg, rsv1, rsv2, rsv3 = ext:encode(text, TEXT, true, false)
  assert_equal('HELLO', msg)
  assert_false(rsv1)
  assert_false(rsv2)
  assert_false(rsv3)

  decode = ext:decode(msg, TEXT, true, rsv1, rsv2, rsv3)
  assert_equal(text, decode)
end

function test_duplicate_rsv_bit_accept()
  assert(ext:reg(E{'permessage-foo', true,
    offer = {foo_param=true};
  }))
  assert(ext:reg(E{'permessage-bar', true,
    offer = {bar_param=true};
  }))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  local _, err = assert_nil(ext:accept(H{{'permessage-bar'}, {'permessage-foo'}}))

  assert_not_nil(err)
  assert_match('%[WSEXT%]', tostring(err))
  assert_match('%[EINVAL%]', tostring(err))
end

function test_no_rsv_bit()
  assert_nil(ext:reg(E{'permessage-foo'}))
end

function test_accept_without_offer()
  assert_error(function()
    ext:accept{}
  end)
end

function test_accept_invalid_extension()
  assert(ext:reg(E{'permessage-foo', true,
    offer = {foo_param=true};
  }))
  assert(ext:reg(E{'permessage-bar', true,
    offer = {bar_param=true};
  }))

  assert_table(D(ext:offer()))
  local response = {{'permessage-baz'}}

  local _, err = assert_nil(ext:accept(H(response)))

  assert_not_nil(err)
  assert_match('%[WSEXT%]', tostring(err))
  assert_match('%[EINVAL%]', tostring(err))
end

function test_accept_multi_ext_with_same_rsv()
  assert(ext:reg(E{'permessage-foo', true,
    offer = {foo_param=true};
  }))
  assert(ext:reg(E{'permessage-bar', true,
    offer = {bar_param=true};
  }))

  assert_table(D(ext:offer()))
  local response = {{'permessage-bar'}, {'permessage-foo'}}

  local _, err = assert_nil(ext:accept(H(response)))
  assert(err)
end

it('should fail accept if first ext fail', function()
  local ERROR = {}
  assert(ext:reg(E{'permessage-foo', true, accept = {nil, ERROR}}))
  assert(ext:reg(E{'permessage-bar', false, true}))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  local _, err = assert_nil(ext:accept(H{{'permessage-foo'}, {'permessage-bar'}}))
  assert_equal(ERROR, err)

  assert_nil(ext:accepted())
  assert_nil(ext:accepted('permessage-foo'))
  assert_nil(ext:accepted('permessage-bar'))
end)

it('should fail accept if second ext fail', function()
  local ERROR = {}
  assert(ext:reg(E{'permessage-foo', true}))
  assert(ext:reg(E{'permessage-bar', false, true, accept = {nil, ERROR}}))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  local _, err = assert_nil(ext:accept(H{{'permessage-foo'}, {'permessage-bar'}}))
  assert_equal(ERROR, err)

  assert_nil(ext:accepted())
  assert_nil(ext:accepted('permessage-foo'))
  assert_nil(ext:accepted('permessage-bar'))
end)

it('should accept multiple ext', function()
  local ERROR = {}
  assert(ext:reg(E{'permessage-foo', true}))
  assert(ext:reg(E{'permessage-bar', false, true}))

  local offer = assert_table(D(ext:offer()))
  assert_equal(2, #offer)
  assert_equal('permessage-foo', offer[1][1])
  assert_equal('permessage-bar', offer[2][1])

  assert(ext:accept(H{{'permessage-bar'}, {'permessage-foo'}}))

  local t = assert_table(ext:accepted())
  assert_equal('permessage-bar', t[1])
  assert_equal('permessage-foo', t[2])
  local _, i = assert_equal('permessage-foo', ext:accepted('permessage-foo'))
  assert_equal(2, i)
  local _, i = assert_equal('permessage-bar', ext:accepted('permessage-bar'))
  assert_equal(1, i)
end)

end
------------------------------------------------------------------

------------------------------------------------------------------
local _ENV = TEST_CASE'Extensions server' if ENABLE then
local it = IT(_ENV or _M)

local ext

function setup()
  ext = Extensions.new()
end

function teardown()
  ext = nil
end

function test_response()
  assert(ext:reg(E{'permessage-foo', true,
    response = function(self, params)
      assert_table(params)
      assert_equal(1, #params)
      local param = assert_table(params[1])
      assert_true(param.param_foo)

      return {param_foo = false}
    end
  }))

  local offer = {
    {'permessage-foo',{param_foo=true}},
  }

  local response = assert_table(D(ext:response(H(offer))))

  assert_equal(1, #response)
  local resp_foo = assert_table(response[1])
  assert_equal('permessage-foo', resp_foo[1])
  assert_table(resp_foo[2])
  assert_equal('false', resp_foo[2].param_foo)
end

it('should accept match', function()
  assert(ext:reg(E{'permessage-foo', true}))

  local offer = {{'permessage-bar'}, {'permessage-foo'}}
  local resp = assert_table(D(ext:response(H(offer))))

  local response = assert_table(D(ext:response(H(offer))))

  assert_equal(1, #response)
  local resp_foo = assert_table(response[1])
  assert_equal('permessage-foo', resp_foo[1])

  assert_equal('permessage-foo', ext:accepted('permessage-foo'))
  assert_nil(ext:accepted('permessage-bar'))
end)

it('should accept first ext with same rsv bit', function()
  assert(ext:reg(E{'permessage-foo', true}))
  assert(ext:reg(E{'permessage-bar', true}))

  local offer = {{'permessage-bar'}, {'permessage-foo'}}
  local resp = assert_table(D(ext:response(H(offer))))

  local response = assert_table(D(ext:response(H(offer))))

  assert_equal(1, #response)
  local resp = assert_table(response[1])
  assert_equal('permessage-bar', resp[1])
end)

it('should accept first option set', function()
  local called = false

  assert(ext:reg(E{'permessage-foo', true, response=function(self, params)
    called = true
    assert_equal(2, #params)
    local param = assert_table(params[1])
    assert_equal('1', param.value)

    param = assert_table(params[2])
    assert_equal('2', param.value)

    return param
  end}))

  local offer = {
    {'permessage-foo', {value = 1}},
    {'permessage-foo', {value = 2}},
  }
  local resp = assert_table(D(ext:response(H(offer))))

  local response = assert_table(D(ext:response(H(offer))))

  assert_equal(1, #response)
  local resp = assert_table(response[1])
  assert_equal('permessage-foo', resp[1])
  assert_equal('2', resp[2].value)

  assert_true(called)
end)

it('should fail accept if first ext fail', function()
  assert(ext:reg(E{'permessage-foo', true, response = 'ERROR'}))
  assert(ext:reg(E{'permessage-bar', false, true}))

  local offer = {{'permessage-bar'}, {'permessage-foo'}}
  local _, err = assert_nil(ext:response(H(offer)))

  assert_equal('ERROR', err)
  assert_nil(ext:accepted())
end)

it('should fail accept if second ext fail', function()
  assert(ext:reg(E{'permessage-foo', true}))
  assert(ext:reg(E{'permessage-bar', false, true, response = 'ERROR'}))

  local offer = {{'permessage-bar'}, {'permessage-foo'}}
  local _, err = assert_nil(ext:response(H(offer)))

  assert_equal('ERROR', err)
  assert_nil(ext:accepted())
end)

end
------------------------------------------------------------------

------------------------------------------------------------------
local _ENV = TEST_CASE'Extensions encode/decode' if ENABLE then
local it = IT(_ENV or _M)

local ext, foo, bar

function setup()
  local function ret(self)
    return self.buffer:prepend(self.prefix):read_all()
  end

  local function reset(self)
    self.buffer:reset()
    self.called     = {
      encode = false;
      decode = false;
    }
    self.size       = 0
    self.do_proceed = nil
    self.do_error   = nil
    return self
  end

  local encode = function(self, opcode, msg, fin)
    self.called.encode = true
    if self.do_error   then return nil, self.do_error end
    self.size   = (self.size or 0) + #msg
    self.buffer:append(msg)
    if fin then return ret(self) end
    if self.do_proceed then return ret(self) end
  end;

  local decode = function(self, opcode, msg, fin)
    self.called.decode = true
    assert_equal(self.prefix, msg:sub(1, #self.prefix))
    if self.do_error   then return nil, self.do_error end
    return msg:sub(#self.prefix + 1)
  end;

  foo = E{'permessage-foo', true, prefix = "permessage-foo/",
    buffer = ut.Buffer.new(), encode = encode, decode = decode, reset = reset
  }

  bar = E{'permessage-bar', false, true, prefix = "permessage-bar/",
    buffer = ut.Buffer.new(), encode = encode, decode = decode, reset = reset
  }

  ext = Extensions.new()

  assert(ext:reg(foo:reset()))

  assert(ext:reg(bar:reset()))

  local offer = assert_table(D(ext:offer()))

  assert(ext:accept(H{{'permessage-bar'}, {'permessage-foo'}}))
end

it('should validate frame', function()
  assert_true (ext:validate_frame(TEXT, true,  false, false))
  assert_true (ext:validate_frame(TEXT, false, true,  false))
  assert_true (ext:validate_frame(TEXT, true,  true,  false))
  assert_true (ext:validate_frame(TEXT, false, false, false))

  assert_false(ext:validate_frame(TEXT, true,  false, true ))
  assert_false(ext:validate_frame(TEXT, false, true,  true ))
  assert_false(ext:validate_frame(TEXT, true,  true,  true ))
  assert_false(ext:validate_frame(TEXT, false, false, true ))
end)

it('basic encode', function()
  assert_equal('permessage-foo/permessage-bar/hello', ext:encode('hello', TEXT, true))
  assert_true(foo.called.encode)
  assert_true(bar.called.encode)
end)

it('basic decode', function()
  assert_equal('hello', ext:decode('permessage-foo/permessage-bar/hello', TEXT, true, true, true))
  assert_true(foo.called.decode)
  assert_true(bar.called.decode)
end)

it('encode - should bar do boffer', function()
  local _, err = assert_nil(ext:encode('hello', TEXT, false))
  assert_nil(err)
  assert_false(foo.called.encode)
  assert_true(bar.called.encode)

  assert_equal('permessage-foo/permessage-bar/helloworld', ext:encode('world', CONTINUATION, true))
end)

it('encode - should foo do boffer', function()
  bar.do_proceed = true

  local _, err = assert_nil(ext:encode('hello', TEXT, false))
  assert_nil(err)
  assert_true(foo.called.encode)
  assert_true(bar.called.encode)

  foo.called.encode = false
  bar.called.encode = false

  assert_equal('permessage-foo/permessage-bar/hellopermessage-bar/world', ext:encode('world', CONTINUATION, true))
  assert_true(foo.called.encode)
  assert_true(bar.called.encode)
end)

it('encode foo return error', function()
  local ERROR = {}
  foo.do_error = ERROR

  local _, err = assert_nil(ext:encode('permessage-foo/permessage-bar/hellopermessage-bar/hello', TEXT, true))
  assert_equal(ERROR, err)
end)

it('encode bar return error', function()
  local ERROR = {}
  bar.do_error = ERROR

  local _, err = assert_nil(ext:encode('permessage-foo/permessage-bar/hellopermessage-bar/hello', TEXT, true))
  assert_equal(ERROR, err)
end)

it('decode foo return error', function()
  local ERROR = {}
  foo.do_error = ERROR

  local _, err = assert_nil(ext:decode('permessage-foo/permessage-bar/hellopermessage-bar/hello', TEXT, true, true, true))
  assert_equal(ERROR, err)
end)

it('decode bar return error', function()
  local ERROR = {}
  bar.do_error = ERROR

  local _, err = assert_nil(ext:decode('permessage-foo/permessage-bar/hellopermessage-bar/hello', TEXT, true, true, true))
  assert_equal(ERROR, err)
end)

end
------------------------------------------------------------------

utils.RUN()