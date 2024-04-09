-- enable warnings so we can see any relevant messages while running
-- tests or benchmarks through this script
warn("@on")

--[[
Imports
--]]

local lu <const> = require('luaunit/luaunit')
local dt <const> = require('datatable')

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
Unit Tests
--]]

-- slot tests
test_slot = {}

function test_slot.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.slot_private)

  local instance = dt.Slot(function (value) return end, function (value) return end)
  lu.assertEquals(countTableKeys(dt.slot_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.slot_private), initial_count)
end

-- TODO: validator method guard rails
-- TODO: formatter method guard rails

-- datatable type tests
test_datatable_type = {}

function test_datatable_type.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.datatable_type_private)

  local instance = dt.DataTable{slot=dt.AnySlot}
  lu.assertEquals(countTableKeys(dt.datatable_type_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.datatable_type_private), initial_count)
end

function test_datatable_type.test_custom_slots()
  local Person <const> = dt.DataTable{
    name=dt.Slot(function (value)
      if type(value) ~= 'string' or string.len(value) == 0 then
        return nil, "custom_name_slot_error"
      end

      return value
    end),
    age=dt.Slot(function (value)
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
    lu.assertTrue(dt.Slot.is(slot))
    expected_slot_names[name] = nil
  end

  lu.assertTrue(countTableKeys(expected_slot_names) == 0)
end

function test_datatable_type.test_default_slots()
  local Person <const> = dt.DataTable{
    alive=dt.BooleanSlot,
    name=dt.StringSlot,
    age=dt.IntegerSlot,
    height=dt.NumberSlot,
    aliases=dt.TableSlot
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
    lu.assertTrue(dt.Slot.is(slot))
    expected_slot_names[name] = nil
  end

  lu.assertTrue(countTableKeys(expected_slot_names) == 0)
end

function test_datatable_type.test_frozen()
  local MutablePerson <const> = dt.DataTable{name=dt.StringSlot}
  lu.assertFalse(MutablePerson.frozen)

  local FrozenPerson <const> = dt.DataTable({name=dt.StringSlot}, {frozen=true})
  lu.assertTrue(FrozenPerson.frozen)
end

function test_datatable_type.test_is_instance()
  local instance <const> = dt.DataTable{slot=dt.AnySlot}
  lu.assertTrue(dt.DataTable.is(instance))
  lu.assertFalse(dt.DataTable.is({}))
end

-- datatable instance tests
test_datatable = {}

function test_datatable.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.datatable_instance_private)

  local Mock <const> = dt.DataTable{slot=dt.AnySlot}
  local instance = Mock{slot='foo'}
  lu.assertEquals(countTableKeys(dt.datatable_instance_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.datatable_instance_private), initial_count)
end

function test_datatable.test_custom_slots()
  local Person <const> = dt.DataTable{
    name=dt.Slot(function (value)
      if type(value) ~= 'string' or string.len(value) == 0 then
        return nil, "custom_name_slot_error"
      end

      return value
    end),
    age=dt.Slot(function (value)
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
  local Person <const> = dt.DataTable{
    alive=dt.BooleanSlot,
    name=dt.StringSlot,
    age=dt.IntegerSlot,
    height=dt.NumberSlot,
    aliases=dt.TableSlot
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
  local Person <const> = dt.DataTable({name=dt.StringSlot}, {frozen=true})
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
  local IntegerRange <const> = dt.DataTable({
    low=dt.IntegerSlot,
    high=dt.IntegerSlot
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
  local Person <const> = dt.DataTable{
    alive=dt.BooleanSlot,
    name=dt.StringSlot,
    age=dt.IntegerSlot,
    height=dt.NumberSlot,
    aliases=dt.TableSlot
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
  local CountA <const> = dt.DataTable{count=dt.IntegerSlot}
  local count_a <const> = CountA{count=10}

  local CountB <const> = dt.DataTable{count=dt.IntegerSlot}
  local count_b <const> = CountB{count=10}

  lu.assertTrue(CountA.is(count_a))
  lu.assertTrue(CountB.is(count_b))

  lu.assertFalse(CountA.is(count_b))
  lu.assertFalse(CountB.is(count_a))

  lu.assertFalse(CountA.is(CountA))
  lu.assertFalse(CountA.is({}))
end

--[[
Command Line Interface
--]]

if os.getenv('LUA_DATATABLE_LEAK_INTERNALS') ~= 'TRUE' then
  error("LUA_DATATABLE_LEAK_INTERNALS environment variable must be 'TRUE' in order to run unit tests")
  os.exit(1)
end

-- run tests
os.exit(lu.LuaUnit.run())
