local uv        = require "lluv"
local websocket = require "websocket"
local Autobahn  = require "./autobahn"
local deflate   = require "websocket.extensions.permessage-deflate"

local ctx do
  local ok, ssl = pcall(require, "lluv.ssl")
  if ok then
    ctx = assert(ssl.context{
      protocol    = "tlsv1",
      certificate = "./wss/server.crt",
    })
  end
end

local Client = function() return websocket.client.lluv{
  ssl                = ctx,
  utf8               = true,
  extensions         = {deflate},
  auto_ping_response = true,
}end

local URI           = arg[1] or "ws://127.0.0.1:9001"
local reportDir     = "./reports/clients"
local agent     = string.format("websocket.client.lluv (%s / %s)",
  jit and jit.version or _VERSION, 
  URI:lower():match("^wss:") and "WSS" or "WS"
)
local caseCount     = 0
local currentCaseId = 0

local function getCaseCount(cont)
  local cli = Client() do

  cli:on_open(function() end)

  cli:on_error(function(...)
    print("WS ERROR:", ...)
  end)

  cli:on_message(function(ws, msg)
    caseCount = tonumber(msg)
    ws:close()
  end)

  cli:on_close(function(ws)
    cont()
  end)

  end

  cli:connect(Autobahn.Server.getCaseCount(URI))
end

local function runTestCase(no, cb)
  local cli = Client() do

  cli:on_open(function()
    print("Executing test case " .. no .. "/" .. caseCount)
  end)

  cli:on_error(function(ws, ...)
    assert(cli == ws)
    cli = nil
    print("WS ERROR:", ...)
  end)

  cli:on_message(function(ws, message, opcode)
    if opcode == websocket.TEXT or opcode == websocket.BINARY then
      cli:send(message, opcode)
    end
  end)

  cli:on_close(function(ws, ...)
    assert(cli == ws)
    cli = nil
    cb(...)
  end)

  end

  cli:connect(Autobahn.Server.runTestCase(URI, no, agent))
end

local function updateReports()
  local cli = Client() do

  cli:on_open(function()
    print("Updating reports ...");
  end)

  cli:on_error(function(...)
    print("WS ERROR:", ...)
  end)

  cli:on_message(function(ws, message, opcode)
    print("Report:", message)
  end)

  cli:on_close(function(ws)
    print("Reports updated.");
    print("Test suite finished!");
  end)

  end

  cli:connect(Autobahn.Server.updateReports(URI, agent))
end

local function runNextCase()
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
