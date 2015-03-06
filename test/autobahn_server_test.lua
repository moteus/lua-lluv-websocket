local uv        = require"lluv"
local websocket = require"lluv.websocket"
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
local agent     = string.format("lluv-websocket (%s / %s)",
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

function isWSEOF(err)
  return err:name() == 'EOF' and err.cat and err:cat() == 'WEBSOCKET'
end

function runTest(cb)
  local currentCaseId = 0
  local server = websocket.new{ssl = ctx, utf8 = true}
  server:bind(url, "echo", function(self, err)
    if err then
      print("Server error:", err)
      return server:close()
    end

    wstest({"-m" ,"fuzzingclient", "-s", "fuzzingclient.json"}, function(code, status)
      server:close(function()
        cb(code, status)
      end)
    end)

    server:listen(function(self, err)
      if err then
        print("Server listen:", err)
        return server:close()
      end

      local cli = server:accept()
      cli:handshake(function(self, err, protocol)
        if err then
          print("Server handshake error:", err)
          return cli:close()
        end

        currentCaseId = currentCaseId + 1
        print("Executing test case " .. tostring(currentCaseId))

        cli:start_read(function(self, err, message, opcode)
          if err then
            if not isWSEOF(err) then
              print("Server read error:", err)
            end
            return cli:close()
          end

          if opcode == websocket.TEXT or opcode == websocket.BINARY then
            cli:write(message, opcode)
          end
        end)
      end)
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
