local ut = require "lluv.utils"

local tappend   = function(t, v) t[#t + 1] = v return t end

local CONTINUATION  = 0

------------------------------------------------------------------
local Error = ut.class() do

local ERRORS = {
  [-1] = "EINVAL";
}

for k, v in pairs(ERRORS) do Error[v] = k end

function Error:__init(no, name, msg, ext, code, reason)
  self._no     = assert(no)
  self._name   = assert(name or ERRORS[no])
  self._msg    = msg    or ''
  self._ext    = ext    or ''
  return self
end

function Error:cat()    return 'WSEXT'    end

function Error:no()     return self._no   end

function Error:name()   return self._name end

function Error:msg()    return self._msg  end

function Error:ext()    return self._ext  end

function Error:__tostring()
  local fmt 
  if self._ext and #self._ext > 0 then
    fmt = "[%s][%s] %s (%d) - %s"
  else
    fmt = "[%s][%s] %s (%d)"
  end
  return string.format(fmt, self:cat(), self:name(), self:msg(), self:no(), self:ext())
end

function Error:__eq(rhs)
  return self._no == rhs._no
end

end
------------------------------------------------------------------

------------------------------------------------------------------
local Extensions = ut.class() do

function Extensions:__init()
  self._by_name     = {}
  self._extensions  = {}
  self._ext_options = {}

  return self
end

function Extensions:reg(ext, opt)
  local name = ext.name

  if not (ext.rsv1 or ext.rsv2 or ext.rsv3) then
    return
  end

  if self._by_name[name] then
    return
  end

  local id = #self._extensions + 1
  self._by_name[name]     = id
  self._extensions[id]    = ext
  self._ext_options[id]   = opt

  return self
end

-- Generate extension negotiation offer
function Extensions:offer()
  local offer, extensions = {}, {}

  for i = 1, #self._extensions do
    local ext = self._extensions[i]
    local extension = ext.client(self._ext_options[i])
    if extension then
      local off = extension:offer()
      if off then
        extensions[ext.name] = extension
        tappend(offer, {extension.name, off})
      end
    end
  end

  self._offered = extensions

  return offer
end

-- Accept extension negotiation response
function Extensions:accept(params)
  assert(self._offered, 'try accept without offer')

  local active, offered = {}, self._offered
  self._offered = nil

  local rsv1, rsv2, rsv3

  for _, param in ipairs(params) do
    local name, options = param[1], param[2]
    local ext = offered[name]

    if not ext then
      return nil, Error.new(Error.EINVAL, nil, 'not offered extensin', name)
    end

    if (rsv1 and ext.rsv1) or (rsv2 and ext.rsv2) or (rsv2 and ext.rsv2) then
      return nil, Error.new(Error.EINVAL, nil, 'more then one extensin with same rsv bit', name)
    end

    local ok, err = ext:accept(options)
    if not ok then return nil, err end

    offered[name] = nil
    tappend(active, ext)
    rsv1 = rsv1 or ext.rsv1
    rsv2 = rsv2 or ext.rsv2
    rsv3 = rsv3 or ext.rsv3
  end

  for name, ext in pairs(offered) do
    --! @todo close ext
  end

  self._active = active

  return self
end

-- Generate extension negotiation response
function Extensions:response(offers)
  local params_by_name = {}
  for _, offer in ipairs(offers) do
    local name, params = offer[1], offer[2]
    if self._by_name[name] then
      params_by_name[name] = params_by_name[name] or {}
      tappend(params_by_name[name], params or {})
    end
  end

  local rsv1, rsv2, rsv3

  local active, response = {}, {}
  for _, offer in ipairs(offers) do
    local name = offer[1]
    local params = params_by_name[name]
    if params then
      params_by_name[name] = nil
      local i              = self._by_name[name]
      local ext            = self._extensions[i]
      -- we accept first extensin with same bits
      if not ((rsv1 and ext.rsv1) or (rsv2 and ext.rsv2) or (rsv2 and ext.rsv2)) then
        local extension  = ext.server(self._ext_options[i])
        -- Client can send invalid or unsupported arguments
        -- if client send invalid arguments then server must close connection
        -- if client send unsupported arguments server should just ignore this extension
        local resp, err = extension:response(params)
        if resp then
          tappend(response, {ext.name, resp})
          tappend(active, extension)
          rsv1 = rsv1 or ext.rsv1
          rsv2 = rsv2 or ext.rsv2
          rsv3 = rsv3 or ext.rsv3
        elseif err then
          return nil, err
        end
      end
    end
  end

  if active[1] then
    self._active = active
    return response
  end
end

function Extensions:validate_frame(opcode, rsv1, rsv2, rsv3)
  local m1, m2, m3

  if self._active then
    for i = 1, #self._active do
      local ext = self._active[i]
      if (ext.rsv1 and rsv1) then m1 = true end
      if (ext.rsv2 and rsv2) then m2 = true end
      if (ext.rsv3 and rsv3) then m3 = true end
    end
  end

  return (m1 or not rsv1) and (m2 or not rsv2) and (m3 or not rsv3)
end

function Extensions:encode(msg, opcode, fin, allows)
  local rsv1, rsv2, rsv3 = false, false, false
  if self._active then
    if allows == nil then allows = true end
    for i = 1, #self._active do
      local ext = self._active[i]
      if (allows ~= false) and ( (allows == true) or (allows[ext.name]) ) then
        local err msg, err  = ext:encode(opcode, msg, fin)
        if not msg then return nil, err end
        rsv1 = rsv1 or ext.rsv1
        rsv2 = rsv2 or ext.rsv2
        rsv3 = rsv3 or ext.rsv3
      end
    end
  end
  if opcode == CONTINUATION then return msg end
  return msg, rsv1, rsv2, rsv3
end

function Extensions:decode(msg, opcode, fin, rsv1, rsv2, rsv3)
  if not (rsv1 or rsv2 or rsv3) then return msg end
  for i = #self._active, 1, -1 do
    local ext = self._active[i]
    if (ext.rsv1 and rsv1) or (ext.rsv2 and rsv2) or (ext.rsv3 and rsv3) then
      local err msg, err = ext:decode(opcode, msg, fin)
      if not msg then return nil, err end
    end
  end
  return msg
end

function Extensions:accepted(name)
  if not self._active then return end

  if name then
    for i = 1, #self._active do
      local ext = self._active[i]
      if ext.name == name then return name, i end
    end
    return
  end

  local res = {}
  for i = 1, #self._active do
    local ext = self._active[i]
    tappend(res, ext.name)
  end
  return res
end

end
------------------------------------------------------------------

return {
  new = Extensions.new
}