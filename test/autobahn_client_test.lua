local uv        = require "lluv"
local websocket = require "lluv.websocket"
local json      = require "cjson"
local path      = require "path"

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
local errors        = {}
local warnings      = {}

function readFile(p)
  p = path.fullpath(p)
  local f = assert(io.open(p, 'rb'))
  local d = f:read("*a")
  f:close()
  return d
end

function readJson(p)
  return json.decode(readFile(p))
end

function cleanDir(p, mask)
  if path.exists(p) then
    path.each(path.join(p, mask), function(P)
      path.remove(P)
    end)
  end
end

function cleanReports(p)
  cleanDir(p, "*.json")
  cleanDir(p, "*.html")
end

function readReport(dir, agent)
  local p = path.join(dir, "index.json")
  if not path.exists(p) then return end
  local t = readJson(p)
  t = t[agent] or {}
  return t
end

function printReport(name, t)
  print("","Test case ID " .. name .. ":")
  for k, v in pairs(t) do
    print("","",k,"=>",v)
  end
  print("-------------")
end

function printReports(name, t)
  print(name .. ":")
  for k, v in pairs(t)do
    printReport(k, v)
  end
end

function isWSEOF(err)
  return err:name() == 'EOF' and err.cat and err:cat() == 'WEBSOCKET'
end

function isEOF(err)
  return err:name() == 'EOF'
end

function getCaseCount(cont)
  websocket.new{ssl = ctx}:connect(URI .. "/getCaseCount", "echo", function(cli, err)
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

function runtTestCase(no, cb)
  local ws_uri = URI .. "/runCase?case=" .. no .. "&agent=" .. agent

  websocket.new{ssl = ctx}:connect(ws_uri, "echo", function(cli, err)
    if err then
      print("Client connect error:", err)
      return cli:close()
    end

    print("Executing test case " .. no .. "/" .. caseCount)

    cli:start_read("*t", function(self, err, message, opcode)
      if err then
        if not isEOF(err) then -- some tests do not make full close handshake(e.g. 3.3)
          print("Client read error:", err)
        end
        return cli:close(cb)
      end

      if opcode == websocket.TEXT or opcode == websocket.BINARY then
        cli:write(message, opcode)
      end

    end)
  end)
end

function runNextCase()
  runtTestCase(currentCaseId, function(_, err, code, reason)
    if code ~= 1000 then
      print("Test fail : ", reason)
    end
    currentCaseId = currentCaseId + 1
    if currentCaseId <= caseCount then
      runNextCase()
    else
      print("All test cases executed.")
      updateReports()
    end
  end)
end

function updateReports()
  local ws_uri = URI .. "/updateReports?agent=" .. agent

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

function runAll()
  currentCaseId = 1
  cleanReports(reportDir)
  getCaseCount(runNextCase)
  uv.run(debug.traceback)
  updateReports()
  uv.run(debug.traceback)

  local report = readReport(reportDir, agent)
  local behavior, behaviorClose = {}, {}

  for name, result in pairs(report) do
    if result.behavior == 'FAILED' then
      errors[name] = result
    elseif result.behavior == 'WARNING' then
      warnings[name] = result
    elseif result.behavior == 'UNIMPLEMENTED' then
      warnings[name] = result
    elseif result.behaviorClose ~= 'OK' then
      warnings[name] = result
    end
  end

  if next(warnings) then
    printReports("WARNING", warnings)
  end

  if next(errors) then
    printReports("ERROR", errors)
    os.exit(-1)
  end
end

runAll()

-- runtTestCase(22, print)

uv.run(debug.traceback)

