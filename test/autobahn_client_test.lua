local uv        = require "lluv"
local websocket = require "lluv.websocket"

local URI           = "ws://127.0.0.1:9001"
local agent         = "lluv-websocket"
local caseCount     = 0
local currentCaseId = 0

function isWSEOF(err)
  return err:name() == 'EOF' and err.cat and err:cat() == 'WEBSOCKET'
end

function getCaseCount(cont)
  websocket.new():connect(URI .. "/getCaseCount", "echo", function(cli, err)
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

  websocket.new():connect(ws_uri, "echo", function(cli, err)
    if err then
      print("Client connect error:", err)
      return cli:close()
    end

    print("Executing test case " .. no .. "/" .. caseCount)

    cli:start_read(function(self, err, message, opcode)
      if err then
        if not isWSEOF(err) then
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

  websocket.new():connect(ws_uri, "echo", function(cli, err)
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
    end)
  end)
end

function runAll()
  currentCaseId = 1
  getCaseCount(runNextCase)
  uv.run()
  updateReports()
end

runAll()

-- runtTestCase(1, print)

uv.run()

