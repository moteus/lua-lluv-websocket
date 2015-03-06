local uv        = require"lluv"
local websocket = require"websocket"
local Autobahn  = require"./autobahn"

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
local agent     = string.format("websocket.server.lluv (%s / %s)",
  jit and jit.version or _VERSION, 
  url:lower():match("^wss:") and "WSS" or "WS"
)
local exitCode  = -1

local config = {
  outdir = reportDir,
  servers = {
    { agent = agent, url = url},
  },
  cases = {"1.*", "2.*", "3.*", "4.*", "5.*", "6.*", "6.2.*", "7.*","10.*"},
  ["exclude-cases"] = {"3.*", "6.4.2", "6.4.3", "6.4.4"},
  ["exclude-agent-cases"] = {},
}

function wstest(args, cb)
  return uv.spawn({
    file = "wstest",
    args = args,
    stdio = {{}, 1, 2}
  }, function(handle, err, status, signal)
    handle:close()
    if err then error("Error spawn:" .. tostring(err)) end
    cb(status, signal)
  end)
end

function runTest(cb)
  local currentCaseId = 0

  local echo = function(cli)
    currentCaseId = currentCaseId + 1
    print("Executing test case " .. tostring(currentCaseId))

    cli:on_error(function(ws, ...)
      print("WS ERROR:", ...)
    end)

    cli:on_message(function(ws, message, opcode)
      if opcode == websocket.TEXT or opcode == websocket.BINARY then
        cli:send(message, opcode)
      end
    end)

    cli:on_close(function(ws, message, opcode)
      assert(cli == ws)
      cli = nil
    end)
  end

  local server = websocket.server.lluv.listen{
    ssl = ctx, utf8 = true, url = url, default = echo,
    protocols = {echo = echo},
    -- logger = require "log".new(require"log.writer.stdout".new(),require"log.formatter.concat".new(' ')),
  }

  uv.timer():start(500, function()
    wstest({"-m" ,"fuzzingclient", "-s", "fuzzingclient.json"}, function(code, status)
      server:close()
      cb(code, status)
    end)
  end)
end

Autobahn.cleanReports(reportDir)

Autobahn.Utils.writeJson("fuzzingclient.json", config)

runTest(function()
  if not Autobahn.verifyReport(reportDir, agent) then
    exitCode = -1
  else
    exitCode = 0
  end

  print"DONE"
end)

uv.run()

os.exit(exitCode)
