local Timer  = require "lzmq".utils.stopwatch

local function timer_start() return Timer():start() end

local function timer_elpsed(t)
  local elapsed = t:stop()
  if elapsed == 0 then elapsed = 1 end
  return elapsed / 1000000
end

local frame1 = require "websocket.frame"
local frame2 = require "lluv.websocket.frame"

local function rand_bin(n)
  local r = {}
  for i = 1, n do
    r[#r + 1] = string.char(math.random(0, 0xFF))
  end
  return table.concat(r)
end

local function gc()
  for i = 1, 1000 do
    collectgarbage("collect")
  end
end

local function bench(name, encode, masked, n, d, min, max)
  local data = {}

  local total_size = 0
  for i = 1, d do
    local size = math.random(min, max)
    local f = rand_bin(size)
    data[#data + 1] = f
    total_size = total_size + #f
  end

  gc()
  local start = timer_start()

  for j = 1, n do
    for i = 1, #data do encode(data[i], frame1.BINARY) end
  end

  local elapsed = timer_elpsed(start)
  local fps     = math.floor((n * d) / elapsed)
  local avg     = math.floor(total_size / d)

  print(string.format("%s: payload %4d[b] masked %d %4d[sec] %4d[frame/sec]",
    name, avg, masked and 1 or 0, math.floor(elapsed), fps
  ))

end

local function bench_all(masked, n, d, min, max)
  bench("Websocket (struct)   ", frame1.encode, masked, n, d, min, max)
  bench("Websocket (bit only) ", frame2.encode, masked, n, d, min, max)
  print("-----------------------------------")
end

bench_all(true,  1000, 10000, 120, 130)
bench_all(true,  1000, 1000, 0xFFFF-10, 0xFFFF+10)
bench_all(false, 1000, 10000, 120, 130)
bench_all(false, 1000, 1000, 0xFFFF-10, 0xFFFF+10)
