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

local datatable_metatable <const> = {}
local datatable_private_data <const> = setmetatable({}, {__mode='k'})

-- public interface
local DataTable <const> = setmetatable({
  create = function (slot_data, flag_data)
    if type(slot_data) ~= 'table' or not next(slot_data) then
      error("DataTable slots must be a non-empty table")
    end

    local flag_data <const> = flag_data or {}
    if type(flag_data) ~= 'table' then
      error("DataTable flags must be a table")
    end

    -- TODO: flags
    -- local frozen <const> = (flag_data['frozen'] == true)

    -- TODO: slots
    local slots <const> = {}

    local instance <const> = {}
    datatable_private_data[instance] = {
      slots=slots,
      frozen=frozen
    }

    return setmetatable(instance, {
      __name = 'DataTable',
      __metatable = datatable_metatable,
      __index = function (self, key)
        local private <const> = assert(
          datatable_private_data[self],
          "DataTable instance not recognized: " .. tostring(self)
        )

        return private.slots[key]
      end,
      __newindex = function (_, _, _)
        error("DataTable definition cannot be modified")
      end,
      __call = function (self, data)
        -- TODO: create instance of datatable with data
      end,
      __gc = function (self)
        datatable_private_data[self] = nil
      end
    })
  end,
  is = function (value)
    return (getmetatable(value) == datatable_metatable)
  end
}, {
  __call = function (self, ...)
    return self.create(...)
  end
})

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

-- datatable tests
test_datatable = {}

function test_datatable.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(datatable_private_data)

  local datatable = DataTable({name='string', age='integer'})
  lu.assertEquals(countTableKeys(datatable_private_data), initial_count + 1)

  datatable = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(datatable_private_data), initial_count)
end

-- run tests
os.exit(lu.LuaUnit.run())
