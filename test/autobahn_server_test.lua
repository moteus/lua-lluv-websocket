local uv   = require"lluv"
local ws   = require"lluv.websocket"
local json = require"cjson"
local path = require"path"

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
local agent     = string.format("lluv-websocket (%s / %s)", jit and jit.version or _VERSION, ctx and "WSS" or "WS")
local exitCode  = -1
local errors    = {}
local warnings  = {}

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

function readFile(p)
  p = path.fullpath(p)
  local f = assert(io.open(p, 'rb'))
  local d = f:read("*a")
  f:close()
  return d
end

function writeFile(p, data)
  local f = assert(io.open(p, "w+"))
  f:write(data)
  f:close()
end

function readJson(p)
  return json.decode(readFile(p))
end

function writeJson(p, t)
  return writeFile(p, json.encode(t))
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

function runTest(cb)

  local currentCaseId = 0
  local server = ws.new{ssl = ctx, utf8 = true}
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

          if opcode == ws.TEXT or opcode == ws.BINARY then
            cli:write(message, opcode)
          end
        end)
      end)
    end)
  end)

end

cleanReports(reportDir)

writeJson("fuzzingclient.json", config)

runTest(function()
  local report = readReport(reportDir, agent)

  if not report then
    exitCode = -2
  else
    exitCode = 0

    for name, result in pairs(report) do
      if result.behavior == 'FAILED' then
        errors[name] = result
      elseif result.behavior == 'WARNING' then
        warnings[name] = result
      elseif result.behavior == 'UNIMPLEMENTED' then
        warnings[name] = result
      elseif result.behaviorClose ~= 'OK' and result.behaviorClose ~= 'INFORMATIONAL' then
        warnings[name] = result
      end
    end


    if next(warnings) then
      printReports("WARNING", warnings)
    end

    if next(errors) then
      printReports("ERROR", errors)
      exitCode = -1
    end
  end

  print"DONE"
end)

uv.run()

os.exit(exitCode)
