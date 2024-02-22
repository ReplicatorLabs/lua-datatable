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
local slot_private <const> = setmetatable({}, {__mode='k'})

-- implementation
local slot_internal_metatable <const> = {
  __name = 'Slot',
  __metatable = slot_metatable,
  __index = function (self, key)
    local private <const> = assert(slot_private[self], "Slot instance not recognized: " .. tostring(self))
    if key == 'validator' or key == 'formatter' then
      return private[key]
    end
  end,
  __newindex = function (_, _, _)
    error("Slot definition cannot be modified")
  end,
  __call = function (self, operation, value)
    local private <const> = assert(slot_private[self], "Slot instance not recognized: " .. tostring(self))
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
    slot_private[self] = nil
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
    slot_private[instance] = {
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

local datatable_type_metatable <const> = {}
local datatable_type_private <const> = setmetatable({}, {__mode='k'})

local datatable_instance_metatable <const> = {}
local datatable_instance_private <const> = setmetatable({}, {__mode='k'})

-- instance implementation
local datatable_instance_internal_metatable <const> = {
  __name = 'DataTable',
  __metatable = datatable_instance_metatable,
  __index = function (self, key)
    local private <const> = assert(
      datatable_instance_private[self],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local datatable <const> = assert(
      datatable_type_private[private.datatable],
      "DataTable type not recognized: " .. tostring(self)
    )

    local slot <const> = assert(datatable.slots[key], "DataTable slot not found: " .. tostring(key))
    return private.data[key]
  end,
  __newindex = function (self, key, value)
    local private <const> = assert(
      datatable_instance_private[self],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local datatable <const> = assert(
      datatable_type_private[private.datatable],
      "DataTable type not recognized: " .. tostring(self)
    )

    local slot <const> = assert(datatable.slots[key], "DataTable slot not found: " .. tostring(key))
    assert(not datatable.frozen, "DataTable type is frozen")

    local value, message = slot('validate', value)
    if message then
      error("DataTable slot '" .. key .. "': " .. message)
    end

    local previous_value <const> = private.data[key]
    private.data[key] = value

    local message = datatable.validator(private.data)
    if message ~= nil then
      private.data[key] = previous_value  -- XXX: is there a better way without a shallow copy of private.data?
      assert(type(message) == 'string', "DataTable validator function must return a string message")
      error("DataTable instance data is not valid: " .. message)
    end
  end,
  __pairs = function (self)
    local private <const> = assert(
      datatable_instance_private[self],
      "DataTable instance not recognized: " .. tostring(self)
    )

    local datatable <const> = assert(
      datatable_type_private[private.datatable],
      "DataTable type not recognized: " .. tostring(self)
    )

    -- note: lua table iteration is in arbitrary order whereas this always
    -- iterates in the same order which is technically backwards compatible
    -- for loops: https://www.lua.org/manual/5.4/manual.html#3.3.5
    local function iterate(keys, key) -- state variable, initial or previous control value
      -- note: not strictly necessary as table.remove({}, 1) and inner[nil]
      -- both return nil so the loop ends on it's own but this is safer
      if #keys == 0 then
        return
      end

      local key <const> = table.remove(keys, 1)
      local value <const> = private.data[key]
      return key, value -- control value, remaining loop values
    end

    local keys <const> = {}
    for name, _ in pairs(datatable.slots) do
      table.insert(keys, name)
    end

    -- iterator function, state variable, initial control value, closing variable
    return iterate, keys, keys[1], nil
  end,
  __gc = function (self)
    datatable_instance_private[self] = nil
  end
}

-- type implementation
local datatable_type_internal_metatable <const> = {
  __name = 'DataTableType',
  __metatable = datatable_type_metatable,
  __index = function (self, key)
    local private <const> = assert(
      datatable_type_private[self],
      "DataTable type not recognized: " .. tostring(self)
    )

    if key == 'slots' then
      -- shallow copy to prevent changing defined slots
      local slots <const> = {}
      for name, slot in pairs(private.slots) do
        slots[name] = slot
      end

      return slots
    elseif key == 'frozen' then
      return private.frozen
    elseif key == 'is' then
      return function (value)
        if getmetatable(value) ~= datatable_instance_metatable then
          return false
        end

        local instance_private <const> = assert(
          datatable_instance_private[value],
          "DataTable instance not recognized: " .. tostring(value)
        )

        return (instance_private.datatable == self)
      end
    else
      return nil
    end

    return private.slots[key]
  end,
  __newindex = function (_, _, _)
    error("DataTable definition cannot be modified")
  end,
  __call = function (self, data)
    local private <const> = assert(
      datatable_type_private[self],
      "DataTable type not recognized: " .. tostring(self)
    )
  
    local initial_data <const> = {}
    for name, slot in pairs(private.slots) do
      local value, message = slot('validate', data[name])
      if message then
        error("DataTable slot '" .. name .. "': " .. message)
      end

      initial_data[name] = value
    end

    local message <const> = private.validator(initial_data)
    if message ~= nil then
      assert(type(message) == 'string', "DataTable validator function must return a string message")
      error("DataTable instance data is not valid: " .. message)
    end

    local instance <const> = {}
    datatable_instance_private[instance] = {
      datatable=self,
      data=initial_data
    }

    return setmetatable(instance, datatable_instance_internal_metatable)
  end,
  __gc = function (self)
    datatable_type_private[self] = nil
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

    local frozen <const> = (flag_data['frozen'] or false)
    if type(frozen) ~= 'boolean' then
      error("DataTable frozen flag must be a boolean")
    end

    local validator <const> = (flag_data['validator'] or (function (_) return end))
    if type(validator) ~= 'function' then
      error("DataTable validator flag must be a function")
    end

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
    datatable_type_private[instance] = {
      slots=slots,
      frozen=frozen,
      validator=validator
    }

    return setmetatable(instance, datatable_type_internal_metatable)
  end,
  is = function (value)
    return (getmetatable(value) == datatable_type_metatable)
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
  local initial_count = countTableKeys(slot_private)

  local slot = Slot(function (value) return end, function (value) return end)
  lu.assertEquals(countTableKeys(slot_private), initial_count + 1)

  slot = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(slot_private), initial_count)
end

-- TODO: validator method guard rails
-- TODO: formatter method guard rails

-- datatable type tests
test_datatable_type = {}

function test_datatable_type.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(datatable_type_private)

  local datatable = DataTable{slot='any'}
  lu.assertEquals(countTableKeys(datatable_type_private), initial_count + 1)

  datatable = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(datatable_type_private), initial_count)
end

function test_datatable_type.test_custom_slots()
  local Person <const> = DataTable{
    name=Slot(function (value)
      if type(value) ~= 'string' or string.len(value) == 0 then
        return nil, "custom_name_slot_error"
      end

      return value
    end),
    age=Slot(function (value)
      if type(value) ~= 'number' or value <= 0 then
        return nil, "custom_age_slot_error"
      end

      return value
    end)
  }

  local expected_slot_names <const> = {
    ['name']=true,
    ['age']=true,
  }

  for name, slot in pairs(Person.slots) do
    lu.assertTrue(expected_slot_names[name])
    lu.assertTrue(Slot.is(slot))
    expected_slot_names[name] = nil
  end

  lu.assertTrue(countTableKeys(expected_slot_names) == 0)
end

function test_datatable_type.test_default_slots()
  local Person <const> = DataTable{
    alive='boolean',
    name='string',
    age='integer',
    height='number',
    aliases='table'
  }

  local expected_slot_names <const> = {
    ['alive']=true,
    ['name']=true,
    ['age']=true,
    ['height']=true,
    ['aliases']=true
  }

  for name, slot in pairs(Person.slots) do
    lu.assertTrue(expected_slot_names[name])
    lu.assertTrue(Slot.is(slot))
    expected_slot_names[name] = nil
  end

  lu.assertTrue(countTableKeys(expected_slot_names) == 0)
end

function test_datatable_type.test_frozen()
  local MutablePerson <const> = DataTable{name='string'}
  lu.assertFalse(MutablePerson.frozen)

  local FrozenPerson <const> = DataTable({name='string'}, {frozen=true})
  lu.assertTrue(FrozenPerson.frozen)
end

function test_datatable_type.test_is_instance()
  local datatable <const> = DataTable{slot='any'}
  lu.assertTrue(DataTable.is(datatable))
  lu.assertFalse(DataTable.is({}))
end

-- datatable instance tests
test_datatable = {}

function test_datatable.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(datatable_instance_private)

  local Mock <const> = DataTable{slot='any'}
  local instance = Mock{slot='foo'}
  lu.assertEquals(countTableKeys(datatable_instance_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(datatable_instance_private), initial_count)
end

function test_datatable.test_custom_slots()
  local Person <const> = DataTable{
    name=Slot(function (value)
      if type(value) ~= 'string' or string.len(value) == 0 then
        return nil, "custom_name_slot_error"
      end

      return value
    end),
    age=Slot(function (value)
      if type(value) ~= 'number' or value <= 0 then
        return nil, "custom_age_slot_error"
      end

      return value
    end)
  }

  local person <const> = Person{name='Jane Doe', age=18}
  lu.assertEquals(person.name, 'Jane Doe')
  lu.assertEquals(person.age, 18)

  person.name = 'Jane Smith'
  person.age = 42

  lu.assertErrorMsgContains(
    "custom_name_slot_error",
    function (i, k, v)
      i[k] = v
    end,
    person,
    'name',
    ''
  )

  lu.assertErrorMsgContains(
    "custom_age_slot_error",
    function (i, k, v)
      i[k] = v
    end,
    person,
    'age',
    -20
  )
end

function test_datatable.test_default_slots()
  local Person <const> = DataTable{
    alive='boolean',
    name='string',
    age='integer',
    height='number',
    aliases='table'
  }

  local john_doe <const> = Person{
    alive=true,
    name='John Doe',
    age=18,
    height=80.5,
    aliases={'Johnny'}
  }

  lu.assertEquals(john_doe.alive, true)
  lu.assertEquals(john_doe.name, 'John Doe')
  lu.assertEquals(john_doe.age, 18)
  lu.assertEquals(john_doe.height, 80.5)
  lu.assertEquals(john_doe.aliases, {'Johnny'})

  john_doe.alive = false
  lu.assertErrorMsgContains(
    "DataTable slot 'alive': slot value must be a boolean",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'alive',
    'not_a_boolean'
  )

  john_doe.name = ''
  lu.assertErrorMsgContains(
    "DataTable slot 'name': slot value must be a string",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'name',
    42
  )

  john_doe.age = 42
  lu.assertErrorMsgContains(
    "DataTable slot 'age': slot value must be an integer",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'age',
    3.14
  )

  john_doe.height = 100
  lu.assertErrorMsgContains(
    "DataTable slot 'height': slot value must be a number",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'height',
    false
  )

  john_doe.aliases = {}
  lu.assertErrorMsgContains(
    "DataTable slot 'aliases': slot value must be a table",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'aliases',
    'hello'
  )
end

function test_datatable.test_frozen()
  local Person <const> = DataTable({name='string'}, {frozen=true})
  local john_doe <const> = Person{name='John Doe'}

  lu.assertErrorMsgContains(
    "DataTable slot not found: missing_slot",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'missing_slot',
    'test'
  )

  lu.assertErrorMsgContains(
    "DataTable type is frozen",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'name',
    'test'
  )
end

function test_datatable.test_validator()
  local IntegerRange <const> = DataTable({
    low='integer',
    high='integer'
  }, {
    validator=(function (data)
      if data.low > data.high then
        return "Range lower bound must not be greater than higher bound"
      end
    end)
  })

  local existing_range <const> = IntegerRange{low=10, high=20}
  existing_range.low = 15
  existing_range.high = 30

  lu.assertErrorMsgContains(
    "Range lower bound must not be greater than higher bound",
    function (i, k, v)
      i[k] = v
    end,
    existing_range,
    'low',
    100
  )

  lu.assertErrorMsgContains(
    "Range lower bound must not be greater than higher bound",
    IntegerRange,
    {low=20, high=10}
  )
end

function test_datatable.test_data_pairs_enumeration()
  local Person <const> = DataTable{
    alive='boolean',
    name='string',
    age='integer',
    height='number',
    aliases='table'
  }

  local data <const> = {
    alive=true,
    name='John Doe',
    age=18,
    height=80.5,
    aliases={'Johnny'}
  }

  local john_doe <const> = Person(data)

  for key, value in pairs(john_doe) do
    lu.assertEquals(data[key], value)
    data[key] = nil
  end

  lu.assertEquals(countTableKeys(data), 0)
end

function test_datatable.test_is_instance()
  local CountA <const> = DataTable{count='integer'}
  local count_a <const> = CountA{count=10}

  local CountB <const> = DataTable{count='integer'}
  local count_b <const> = CountB{count=10}

  lu.assertTrue(CountA.is(count_a))
  lu.assertTrue(CountB.is(count_b))

  lu.assertFalse(CountA.is(count_b))
  lu.assertFalse(CountB.is(count_a))

  lu.assertFalse(CountA.is(CountA))
  lu.assertFalse(CountA.is({}))
end

-- run tests
os.exit(lu.LuaUnit.run())
