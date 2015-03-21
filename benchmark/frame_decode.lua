local Timer  = require "lzmq".utils.stopwatch

local function timer_start() return Timer():start() end

local function timer_elpsed(t)
  local elapsed = t:stop()
  if elapsed == 0 then elapsed = 1 end
  return elapsed / 1000000
end

local frame1 = require "websocket.frame"
local frame2 = require "lluv.websocket.frame"

local min_frame_size       = 125
local max_frame_size       = 125
local num_frame_per_packet = 100
local num_of_iteration     = 10000
local masked               = true

local MARK_LINE = "---------------------------------------"
----------------------------------------------------------

local function decode(fn)
  return function(s)
    local data, fin, opcode, mask
    while true do
      data, fin, opcode, s, mask = fn(s)
      if not data then break end
    end
  end
end

local function decode_pos(fn)
  return function(s)
    local pos, data, fin, opcode, mask = 1
    while true do
      data, fin, opcode, pos, mask = fn(s, pos)
      if not data then break end
    end
  end
end

local function rand_bin(n)
  local r = {}
  for i = 1, n do
    r[#r + 1] = string.char(math.random(0, 0xFF))
  end
  return table.concat(r)
end

local function make_packet(size, masked)
  local data = rand_bin(size)
  return frame1.encode(data, frame1.BINARY, masked), data
end

local function make_packets(n, masked, min, max)
  local t = {}
  if not max then max = min end
  for i = 1, n do
    local size = math.random(min, max)
    t[#t+1] = make_packet(size, masked)
  end
  return table.concat(t)
end

local function gc()
  for i = 1, 1000 do
    collectgarbage("collect")
  end
end

local function bench(name, decode, masked, min, max, n, m)
  local packet = make_packets(n, masked, min, max)

  gc()

  local watch = timer_start()

  for i = 1, m do decode(packet) end

  local elapsed = timer_elpsed(watch)
  local fps     = math.floor((n * m) / elapsed)
  local avg     = math.floor(#packet / n)

  print(string.format("%s: frame %4d[b] masked %d %4d[sec]  %4d[frame/packet] %4d[frame/sec]",
    name, avg, masked and 1 or 0, math.floor(elapsed), n, fps
  ))
end

local function bench_all(masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
  bench("Websocket (struct)      ", decode(frame1.decode),            masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
  bench("Websocket (bit only)    ", decode(frame2.decode),            masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
  bench("Websocket (bit only/pos)", decode_pos(frame2.decode_by_pos), masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
  print(MARK_LINE)
end

local function verify(pos, fn, n, masked, min, max)
  local packets, frames = {}, {}
  if not max then max = min end
  for i = 1, 10 do
    local size = math.random(min, max)
    local pack, data = make_packet(size, masked)
    packets[#packets + 1] = pack
    frames[#frames + 1]  = data
  end

  local i, s = 0, table.concat(packets)

  local data, fin, opcode, mask

  local function next_check()
    i = i + 1
    assert(data    == frames[i])
    assert(fin     == true)
    assert(opcode  == frame1.BINARY)
    assert(mask    == (not not masked))
  end

  if pos then
    pos = 1
    while true do
      data, fin, opcode, pos, mask = fn(s, pos)
      if not data then break end
      next_check()
    end
  else
    while true do
      data, fin, opcode, s, mask = fn(s)
      if not data then break end
      next_check()
    end
  end
  assert(i == #frames)
end

local function verify_all()
  verify(false, frame1.decode,        100, true, 125, 128)
  verify(false, frame2.decode,        100, true, 125, 128)
  verify(true,  frame2.decode_by_pos, 100, true, 125, 128)

  verify(false, frame1.decode,        100, false, 125, 128)
  verify(false, frame2.decode,        100, false, 125, 128)
  verify(true,  frame2.decode_by_pos, 100, false, 125, 128)

  verify(false, frame1.decode,        100, true, 0xFFFF-10, 0xFFFF+10)
  verify(false, frame2.decode,        100, true, 0xFFFF-10, 0xFFFF+10)
  verify(true,  frame2.decode_by_pos, 100, true, 0xFFFF-10, 0xFFFF+10)

  verify(false, frame1.decode,        100, false, 0xFFFF-10, 0xFFFF+10)
  verify(false, frame2.decode,        100, false, 0xFFFF-10, 0xFFFF+10)
  verify(true,  frame2.decode_by_pos, 100, false, 0xFFFF-10, 0xFFFF+10)
  
  print("Verify done")
  print(MARK_LINE)
end

print(MARK_LINE)
print("Lua  version: " .. (_G.jit and _G.jit.version or _G._VERSION))
print(MARK_LINE)
print("")

verify_all()
bench_all (true,  125, 125, 1,    1000000   )
bench_all (true,  125, 125, 100,  10000     )
bench_all (true,  125, 125, 1000, 1000      )
bench_all (false, 125, 125, 1,    100000000 )
bench_all (false, 125, 125, 100,  100000    )
bench_all (false, 125, 125, 1000, 10000     )
