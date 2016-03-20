local uv          = require "lluv"
local websocket   = require "lluv.websocket"
local Autobahn    = require "./autobahn"
deflate           = require "websocket.extensions.permessage-deflate"

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

local reportDir   = "./reports/servers"
local url         = arg[1] or "ws://127.0.0.1:9000"
local agent       = string.format("lluv-websocket (%s / %s)",
  jit and jit.version or _VERSION, 
  url:lower():match("^wss:") and "WSS" or "WS"
)
local exitCode    = -1
local read_pat    = arg[2] or "*s"
local decode_mode = arg[3] or "pos"
local verbose   = false

local config = {
  outdir = reportDir,
  servers = {
    { agent = agent, url = url},
  },
  -- cases = {"9.*"}, -- perfomance
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

if read_pat == '*f' then
  -- wstest 0.7.1
  ----
  -- Remote side detect invalid utf8 earlier than me
  -- Problem in ut8 validator which detect it too late
  --
  table.insert(config["exclude-cases"], "6.3.2")
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

function isWSEOF(err)
  return err:name() == 'EOF' and err.cat and err:cat() == 'WEBSOCKET'
end

function runTest(cb)
  print(" URL:", url)
  print("MODE:", read_pat .. "/" .. decode_mode)

  local currentCaseId = 0
  local server = websocket.new{ssl = ctx, utf8 = true}
  server:register(deflate)
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
      if decode_mode == "chunk" then
        cli._on_raw_data = assert(websocket.__on_raw_data_by_chunk)
      end

      currentCaseId = currentCaseId + 1
      if verbose then
        print("Handshake test case " .. tostring(currentCaseId))
      end

      cli:handshake(function(self, err, protocol)
        if err then
          print("Server handshake error:", err)
          return cli:close()
        end

        print("Executing test case " .. tostring(currentCaseId))

        cli:start_read(read_pat, function(self, err, message, opcode, fin)
          if err then
            if not isWSEOF(err) then
              print("Server read error:", err)
            end
            return cli:close()
          end

          if opcode == websocket.CONTINUATION or opcode == websocket.TEXT or opcode == websocket.BINARY then
            cli:write(message, opcode, fin)
          end
        end)
      end)
    end)
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

uv.run()

os.exit(exitCode)
