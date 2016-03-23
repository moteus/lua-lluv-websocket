local uv       = require "lluv"
uv.ws          = require "lluv.websocket"
local Autobahn = require "./autobahn"
local deflate  = require "websocket.extensions.permessage-deflate"

local ctx do
  local ok, ssl = pcall(require, "lluv.ssl")
  if ok then
    ctx = assert(ssl.context{
      protocol    = "tlsv1",
      certificate = "./wss/server.crt",
    })
  end
end

local URI           = arg[1] or "ws://127.0.0.1:9001"
local reportDir     = "./reports/clients"
local agent       = string.format("lluv-websocket (%s / %s)",
  jit and jit.version or _VERSION, 
  url:lower():match("^wss:") and "WSS" or "WS"
)
local caseCount     = 0
local currentCaseId = 0

function isWSEOF(err)
  return err:name() == 'EOF' and err.cat and err:cat() == 'WEBSOCKET'
end

function isEOF(err)
  return err:name() == 'EOF'
end

function getCaseCount(cont)
  local ws_uri = Autobahn.Server.getCaseCount(URI)

  uv.ws{ssl = ctx}:connect(ws_uri, "echo", function(cli, err)
    if err then
      print("Client connect error:", err)
      return cli:close()
    end

    cli:start_read(function(self, err, message, opcode)
      if err then
        print("Client read error:", err)
        return cli:close()
      end

      caseCount = tonumber(message)

      cli:close(function() cont() end)

    end)
  end)
end

function runTestCase(no, cb)
  local ws_uri = Autobahn.Server.runTestCase(URI, no, agent)

  uv.ws{ssl = ctx, utf8 = true, auto_ping_response=true}
  :register(deflate)
  :connect(ws_uri, "echo", function(cli, err)
    if err then
      print("Client connect error:", err)
      return cli:close()
    end

    print("Executing test case " .. no .. "/" .. caseCount)

    cli:start_read("*t", function(self, err, message, opcode, fin)
      if err then
        if not isEOF(err) then -- some tests do not make full close handshake(e.g. 3.3)
          print("Client read error:", err)
        end
        return cli:close(cb)
      end

      if opcode == uv.ws.TEXT or opcode == uv.ws.BINARY or opcode == uv.ws.CONTINUATION then
        cli:write(message, opcode, fin)
      end
      if opcode == uv.ws.PING then
        cli:write(message, uv.ws.PONG, fin)
      end
    end)
  end)
end

function updateReports()
  local ws_uri = Autobahn.Server.updateReports(URI, agent)

  uv.ws{ssl = ctx}:connect(ws_uri, "echo", function(cli, err)
    if err then
      print("Client connect error:", err)
      return cli:close()
    end

    print("Updating reports ...");

    cli:start_read(function(self, err, message, opcode)
      if err then
        if not isWSEOF(err) then
          print("Client read error:", err)
        end

        return cli:close(function()
          print("Reports updated.");
          print("Test suite finished!");
        end)
      end

      print("Report:", message)
    end)
  end)
end

function runNextCase()
  runTestCase(currentCaseId, function(_, err, code, reason)
    currentCaseId = currentCaseId + 1
    if currentCaseId <= caseCount then
      runNextCase()
    else
      print("All test cases executed.")
      updateReports()
    end
  end)
end

local function runAll()
  currentCaseId = 1
  Autobahn.cleanReports(reportDir)
  getCaseCount(runNextCase)
  uv.run(debug.traceback)

  if not Autobahn.verifyReport(reportDir, agent, true) then
    return os.exit(-1)
  end
end

runAll()

-- runTestCase(1, print) uv.run(debug.traceback)
