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

-- implementation
local slot_internal_metatable <const> = {
  __name = 'Slot',
  __metatable = slot_metatable,
  __index = function (self, key)
    local private <const> = assert(slot_private_data[self], "Slot instance not recognized: " .. tostring(self))
    if key == 'validator' or key == 'formatter' then
      return private[key]
    end
  end,
  __newindex = function (_, _, _)
    error("Slot definition cannot be modified")
  end,
  __call = function (self, operation, value)
    local private <const> = assert(slot_private_data[self], "Slot instance not recognized: " .. tostring(self))
    if operation == 'validate' then
      local value, message = private.validator(value)

      if type(message) == 'string' then
        if value ~= nil then
          error("Slot validator returned a value and an error message")
        end
      elseif message ~= nil then
        error("Slot validator message must be a string or nil")
      end

      return value, message
    elseif operation == 'format' then
      local string_representation <const> = private.formatter(value)
      assert(type(string_representation) == 'string', "Slot formatter did not return a string")
      return string_representation
    else
      error("Slot unknown operation: " .. tostring(operation))
    end
  end,
  __gc = function (self)
    slot_private_data[self] = nil
  end
}

-- public interface
local Slot <const> = setmetatable({
  create = function (validator, formatter)
    if type(validator) ~= 'function' then
      error("Slot validator must be a function")
    end

    local formatter <const> = formatter or tostring
    if type(formatter) ~= 'function' then
      error("Slot formatter must be a function")
    end

    local instance <const> = {}
    slot_private_data[instance] = {
      validator=validator,
      formatter=formatter
    }

    return setmetatable(instance, slot_internal_metatable)
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
Default Slots
--]]

local default_slots <const> = {
  ['any'] = Slot.create(function (value) return value end),
  ['boolean'] = Slot.create(function (value)
    if type(value) == 'boolean' then
      return value
    else
      return nil, "slot value must be a boolean"
    end
  end),
  ['string'] = Slot.create(function (value)
    if type(value) == 'string' then
      return value
    else
      return nil, "slot value must be a string"
    end
  end, function (value)
    return '"' .. tostring(value) .. '"'
  end),
  ['number'] = Slot.create(function (value)
    if type(value) == 'number' then
      return value
    else
      return nil, "slot value must be a number"
    end
  end),
  ['integer'] = Slot.create(function (value)
    if math.type(value) == 'integer' then
      return value
    else
      return nil, "slot value must be an integer"
    end
  end),
  ['float'] = Slot.create(function (value)
    if math.type(value) == 'float' then
      return value
    else
      return nil, "slot value must be a float"
    end
  end),
  ['table'] = Slot.create(function (value)
    if type(value) == 'table' then
      return value
    else
      return nil, "slot value must be a table"
    end
  end, function (value)
    return "{...}"
  end)
}

--[[
DataTable
--]]

local datatable_metatable <const> = {}
local datatable_private_data <const> = setmetatable({}, {__mode='k'})

local datatable_instance_metatable <const> = {}
local datatable_instance_private_data <const> = setmetatable({}, {__mode='k'})

-- instance implementation
local datatable_instance_internal_metatable <const> = {
  __name = 'DataTableInstance',
  __metatable = datatable_instance_metatable,
  __index = function (self, key)
    local private <const> = assert(
      datatable_instance_private_data[self],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local datatable <const> = assert(
      datatable_private_data[private.datatable],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local slot <const> = assert(datatable.slots[key], "DataTable slot not found: " .. tostring(key))
    return private.data[key]
  end,
  __newindex = function (self, key, value)
    local private <const> = assert(
      datatable_instance_private_data[self],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local datatable <const> = assert(
      datatable_private_data[private.datatable],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local slot <const> = assert(datatable.slots[key], "DataTable slot not found: " .. tostring(key))
    local value, message = slot('validate', value)
    if message then
      error("DataTable slot '" .. key .. "': " .. message)
    end

    private.data[key] = value
  end,
  __gc = function (self)
    datatable_instance_private_data[self] = nil
  end
}

-- implementation
local datatable_internal_metatable <const> = {
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
    local private <const> = assert(
      datatable_private_data[self],
      "DataTable instance not recognized: " .. tostring(self)
    )
  
    local initial_data <const> = {}
    for name, slot in pairs(private.slots) do
      local value, message = slot('validate', data[name])
      if message then
        error("DataTable slot '" .. name .. "': " .. message)
      end

      initial_data[name] = value
    end

    -- TODO: create instance of datatable with data
    local instance <const> = {}
    datatable_instance_private_data[instance] = {
      datatable=self,
      data=initial_data
    }

    return setmetatable(instance, datatable_instance_internal_metatable)
  end,
  __gc = function (self)
    datatable_private_data[self] = nil
  end
}

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

    local frozen <const> = (flag_data['frozen'] == true)

    local slots <const> = {}
    for name, value in pairs(slot_data) do
      if type(name) ~= 'string' or string.len(name) == 0 then
        error("DataTable slot name must be a non-empty string")
      end

      -- XXX: can this ever happen?
      if slots[name] then
        error("DataTable duplicate slot name: " .. tostring(name))
      end

      if Slot.is(value) then
        slots[name] = value
      elseif type(value) == 'string' then
        slots[name] = assert(default_slots[value], "DataTable unsupported default slot: " .. tostring(value))
      elseif type(value) == 'table' then
        slots[name] = Slot.create(table.unpack(value))
      else
        error("DataTable invalid slot value: " .. tostring(value))
      end
    end

    local instance <const> = {}
    datatable_private_data[instance] = {
      slots=slots,
      frozen=frozen
    }

    return setmetatable(instance, datatable_internal_metatable)
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

  local slot = Slot(function (value) return end, function (value) return end)
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

function test_datatable.test_wip()
  local Person <const> = DataTable({name='string', age='integer'})
  local john_doe <const> = Person{name='John Doe', age=18}
  lu.assertEquals(john_doe.name, 'John Doe')
  lu.assertEquals(john_doe.age, 18)
end

-- run tests
os.exit(lu.LuaUnit.run())
