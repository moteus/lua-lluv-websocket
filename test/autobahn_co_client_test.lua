local trace = function() end -- and function(...) print(os.date("[TST][%x %X]"), ...) end

local uv        = require "lluv"
local ut        = require "lluv.utils"
local socket    = require "lluv.websocket.luasocket"
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

local Client = function() return socket.ws{ssl = ctx, utf8 = true, extensions = {deflate}} end

local URI           = arg[1] or "ws://127.0.0.1:9001"
local reportDir     = "./reports/clients"
local agent       = string.format("lluv.ws.luasocket (%s / %s)",
  jit and jit.version or _VERSION, 
  URI:lower():match("^wss:") and "WSS" or "WS"
)
local agent         = ""
local caseCount     = 0
local currentCaseId = 0

local function getCaseCount(cont)
  ut.corun(function()
    local cli = Client()
    local ok, err = cli:connect(Autobahn.Server.getCaseCount(URI))
    if not ok then
      cli:close()
      return print("WS ERROR:", err)
    end
    local msg = cli:receive("*r")
    caseCount = tonumber(msg)
    cli:close()
    cont()
  end)
end

local function runTestCase(no, cb)
  ut.corun(function()
    local cli = Client()
    trace("Connect")
    local ok, err = cli:connect(Autobahn.Server.runTestCase(URI, no, agent))
    if not ok then
      cli:close()
      return print("WS ERROR:", err)
    end

    print("Executing test case " .. no .. "/" .. caseCount)

    while true do
      trace("receiving...", cli)
      local msg, opcode, fin = cli:receive("*l")
      trace("received", opcode, fin, msg)
      if not msg then break end
      if opcode == socket.TEXT or opcode == socket.BINARY then
        trace("sending...", cli)
        trace("sended", cli:send(msg, opcode))
        trace("After", cli)
      end
      if opcode == socket.PING then
        cli:send(msg, socket.PONG)
      end
    end

    trace("Closing...", cli)
    trace("Closed", cli:close())

    uv.defer(cb)
  end)
end

local function updateReports()
  ut.corun(function()
    local cli = Client()
    local ok, err = cli:connect(Autobahn.Server.updateReports(URI, agent))
    if not ok then print("WS ERROR:", err) end
    cli:close()
  end)
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

-- runTestCase(50, print) uv.run(debug.traceback)