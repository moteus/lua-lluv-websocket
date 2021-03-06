local uv        = require "lluv"
local ut        = require "lluv.utils"
local websocket = require "lluv.websocket.luasocket"
local Autobahn  = require "./autobahn"
local deflate   = require "websocket.extensions.permessage-deflate"

local ctx do
  local ok, ssl = pcall(require, "lluv.ssl")
  if ok then
    ctx = assert(ssl.context{
      protocol    = "tlsv1",
      key         = "./wss/server.key",
      certificate = "./wss/server.crt",
    })
  end
end

local reportDir = "./reports/servers"
local url       = arg[1] or "ws://127.0.0.1:9000"
local agent     = string.format("lluv-co-websocket (%s / %s)",
  jit and jit.version or _VERSION, 
  url:lower():match("^wss:") and "WSS" or "WS"
)
local exitCode  = -1
local read_pat  = arg[2] or "*l"
local verbose   = false

local config = {
  outdir = reportDir,
  servers = {
    { agent = agent, url = url},
  },
  -- cases = {"9.*"}, -- perfomance
  -- cases = {"7.*", "10.*"},
  cases = {"1.*", "2.*", "3.*", "4.*", "5.*", "6.*", "6.2.*", "7.*","10.*","12.1.1"},
  ["exclude-cases"] = {"6.4.2", "6.4.3", "6.4.4"},
  ["exclude-agent-cases"] = {},
}

if os.getenv('TRAVIS') == 'true' then
  -- wstest 0.7.1
  ----
  -- it takes too long to execute this test on Travis
  -- so wstest start next test `7.3.1` and get handshake timeout
  -- and it fails
  table.insert(config["exclude-cases"], "7.1.6")
end

if read_pat == '*r' then
  -- wstest 0.7.1
  ----
  -- Remote side detect invalid utf8 earlier than me
  -- Problem in ut8 validator which detect it too late
  --
  table.insert(config["exclude-cases"], "6.3.2")
  ----
  -- Remote side send TEXT CONT CONT CLOSE
  -- we echod TEXT and while do write operation
  -- we proceed CONT CONT (store them in buffer)
  -- and response to `CLOSE`.
  --
  table.insert(config["exclude-cases"], "6.1.2")
end

function wstest(args, cb)
  return uv.spawn({
    file = "wstest",
    args = args,
    stdio = {{}, verbose and 1 or {}, verbose and 2 or {}}
  }, function(handle, err, status, signal)
    handle:close()
    if err then error("Error spawn:" .. tostring(err)) end
    cb(status, signal)
  end)
end

function runTest(cb)
  local currentCaseId = 0

  local function on_connect(cli)
    currentCaseId = currentCaseId + 1
    print("Executing test case " .. tostring(currentCaseId))

    while true do
      local message, opcode, fin = cli:receive(read_pat)
      if not message then
        if opcode ~= 'closed' then
          print("Server read error:", opcode)
        end
        break
      end

      if opcode == websocket.CONTINUATION or opcode == websocket.TEXT or opcode == websocket.BINARY then
        cli:send(message, opcode, fin)
      end

      if opcode == websocket.PING then
        cli:send(message, websocket.PONG, fin)
      end
    end
    return cli:close()
  end

  ut.corun(function()
    local server = websocket.ws{ssl = ctx, utf8 = true, extensions = {deflate}}
    local ok, err = server:bind(url, 'echo')

    if not ok then
      print("Server bind error:", err)
      return server:close()
    end

    wstest({"-m" ,"fuzzingclient", "-s", "fuzzingclient.json"}, function(code, status)
      -- server:interrupt('interrupted')
      server:close()
      uv.defer(cb, code, status)
    end)

    while true do
      local cli, proto, headers = server:accept()
      if cli then ut.corun(function()
        on_connect(cli:attach())
      end) else
        print("Accept error:", proto)
        break
      end
    end

    server:close()
  end)
end

Autobahn.cleanReports(reportDir)

Autobahn.Utils.writeJson("fuzzingclient.json", config)

runTest(function()
  if not Autobahn.verifyReport(reportDir, agent, true) then
    exitCode = -1
  else
    exitCode = 0
  end

  print"DONE"
end)

uv.run(debug.traceback)

os.exit(exitCode)
