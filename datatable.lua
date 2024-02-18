--[[
Lua Version Check
--]]

local supported_lua_versions <const> = {['Lua 5.4']=true}
if not supported_lua_versions[_VERSION] then
  warn("lua-datatable: detected unsupported lua version: " .. tostring(_VERSION))
end

--[[
Slot
--]]

local slot_metatable <const> = {}
local slot_private_data <const> = setmetatable({}, {__mode='k'})

-- public interface
local Slot <const> = setmetatable({
  create = function (required, validator, formatter)
    if type(required) ~= 'boolean' then
      error("Slot required must be a boolean")
    end

    if type(validator) ~= 'function' then
      error("Slot validator must be a function")
    end

    if type(formatter) ~= 'function' then
      error("Slot formatter must be a function")
    end

    local instance <const> = {}
    slot_private_data[instance] = {
      required=required,
      validator=validator,
      formatter=formatter
    }

    return setmetatable(instance, {
      __name = 'Slot',
      __metatable = slot_metatable,
      __index = function (self, key)
        local private <const> = assert(slot_private_data[self], "Slot instance not recognized: " .. tostring(self))
        if key == 'required' or key == 'validator' or key == 'formatter' then
          return private[key]
        end
      end,
      __newindex = function (_, _, _)
        error("Slot definition cannot be modified")
      end,
      __call = function (self, operation, value)
        local private <const> = assert(slot_private_data[self], "Slot instance not recognized: " .. tostring(self))
        if operation == 'validate' then
          -- TODO: call('validate', value) -> value, message
          return
        elseif operation == 'format' then
          -- TODO: call('format', value) -> string repr
          return
        else
          error("Slot unknown operation: " .. tostring(operation))
        end
      end,
      __gc = function (self)
        slot_private_data[self] = nil
      end
    })
  end,
  is = function (value)
    return (getmetatable(value) == slot_metatable)
  end
}, {
  __call = function (self, ...)
    return self.create(...)
  end
})

--[[
DataTable
--]]

-- TODO

--[[
Module Interface
--]]

-- check if we're being loaded as a module
-- https://stackoverflow.com/a/49376823
if pcall(debug.getlocal, 4, 1) then
  return {Slot=Slot, DataTable=DataTable}
end

--[[
Utilities
--]]

local function countTableKeys(value)
  local keys = {}
  for key, _ in pairs(value) do
    table.insert(keys, key)
  end

  return #keys
end

--[[
Command Line Interface
--]]

local lu <const> = require('luaunit/luaunit')

-- slot tests
test_slot = {}

function test_slot.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(slot_private_data)

  local slot = Slot(true, function (value) return end, function (value) return end)
  lu.assertEquals(countTableKeys(slot_private_data), initial_count + 1)

  slot = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(slot_private_data), initial_count)
end

-- TODO: datatable tests

-- run tests
os.exit(lu.LuaUnit.run())
