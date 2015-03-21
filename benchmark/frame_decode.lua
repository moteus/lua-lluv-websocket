local Timer  = require "lzmq".utils.stopwatch

local function timer_start() return Timer():start() end

local function timer_elpsed(t)
  local elapsed = t:stop() / 1000000
  if elapsed == 0 then elapsed = 1 end
  return elapsed
end

local frame1 = require "websocket.frame"
local frame2 = require "lluv.websocket.frame"

local min_frame_size       = 125
local max_frame_size       = 125
local num_frame_per_packet = 100
local num_of_iteration     = 10000
local masked               = true
----------------------------------------------------------

local function decode(fn)
  return function(s)
    local data, fin, opcode, mask
    while s do
      data, fin, opcode, s, mask = fn(s)
    end
  end
end

local function decode_pos(fn)
  return function(s)
    local pos = 1
    local data, fin, opcode, mask
    while pos do
      data, fin, opcode, pos, mask = fn(s, pos)
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
  return frame1.encode(data, frame1.BINARY, masked)
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

local function bench(name, decode, masked, min, max, n, m)
  local packet = make_packets(n, masked, min, max)

  local watch = timer_start()

  for i = 1, m do decode(packet) end

  local elapsed = timer_elpsed(watch)
  local fps     = math.floor((n * m) / elapsed)
  local avg     = math.floor(#packet / num_frame_per_packet)

  print(string.format("%s: frame %.4d[b] masked %d %.4d[sec]  %4d[frame/packet] %.4d[frame/sec]",
    name, avg, masked and 1 or 0, elapsed, n, fps
  ))
end

bench("Websocket (struct)      ", decode(frame1.decode),            masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
bench("Websocket (bit only)    ", decode(frame2.decode),            masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
bench("Websocket (bit only/pos)", decode_pos(frame2.decode_by_pos), masked, min_frame_size, max_frame_size, num_frame_per_packet, num_of_iteration)
