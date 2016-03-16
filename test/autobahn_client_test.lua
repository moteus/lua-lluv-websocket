local uv          = require "lluv"
local websocket   = require "lluv.websocket"
local Autobahn    = require "./autobahn"
websocket.deflate = require "lluv.websocket.extensions.permessage-deflate"

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
local agent         = "lluv-websocket"
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

  websocket.new{ssl = ctx}:connect(ws_uri, "echo", function(cli, err)
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

  websocket
  .new{ssl = ctx, utf8 = true}
  :register(websocket.deflate)
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

      if opcode == websocket.TEXT or opcode == websocket.BINARY or opcode == websocket.CONTINUATION then
        cli:write(message, opcode, fin)
      end

    end)
  end)
end

function updateReports()
  local ws_uri = Autobahn.Server.updateReports(URI, agent)

  websocket.new{ssl = ctx}:connect(ws_uri, "echo", function(cli, err)
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
