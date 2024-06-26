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

function test_slot.test_create_array_table_slot()
  local values_slot <const> = dt.IntegerSlot
  local array_slot <const> = dt.create_array_table_slot{
    contiguous=true,
    min_keys=3,
    max_keys=5,
    values=values_slot
  }

  lu.assertTrue(dt.Slot.is(array_slot))

  local valid_value <const> = {1, 2, 3, 4}
  local value, message = array_slot('validate', valid_value)
  lu.assertEquals(value, valid_value)
  lu.assertNil(message)

  local value, message = array_slot('validate', {})
  lu.assertNil(value)
  lu.assertEquals(message, "array must contain at least 3 keys")

  local value, message = array_slot('validate', {1, 2, 3, 4, 5, 6})
  lu.assertNil(value)
  lu.assertEquals(message, "array must contain no more than 5 keys")

  local value, message = array_slot('validate', {1, 2, 3, [10]=4})
  lu.assertNil(value)
  lu.assertEquals(message, "array must be contiguous")

  local value, message = array_slot('validate', {['foo']=1})
  lu.assertNil(value)
  lu.assertEquals(message, "array table keys must be integers")

  local invalid_value <const> = 10.5
  local internal_value, internal_message = values_slot('validate', invalid_value)
  lu.assertNil(internal_value)
  lu.assertTrue(string.len(internal_message) > 0)

  local value, message = array_slot('validate', {invalid_value})
  lu.assertNil(value)
  lu.assertEquals(message, "array table value invalid: " .. internal_message)

  -- TODO: formatting
end

function test_slot.test_create_map_table_slot()
  local keys_slot <const> = dt.StringSlot
  local values_slot <const> = dt.IntegerSlot
  local map_slot <const> = dt.create_map_table_slot{
    keys=keys_slot,
    values=values_slot
  }

  lu.assertTrue(dt.Slot.is(map_slot))

  local valid_value <const> = {['score']=10}
  local value, message = map_slot('validate', valid_value)
  lu.assertEquals(value, valid_value)
  lu.assertNil(message)

  local invalid_map_key <const> = 10.5
  local internal_key_value, internal_key_message = keys_slot('validate', invalid_map_key)
  lu.assertNil(internal_key_value)
  lu.assertTrue(string.len(internal_key_message) > 0)

  local invalid_map_by_key <const> = {[invalid_map_key]=10}
  local value, message = map_slot('validate', invalid_map_by_key)
  lu.assertNil(value)
  lu.assertEquals(message, "map table key: " .. internal_key_message)

  local invalid_map_value <const> = 10.5
  local internal_value_value, internal_value_message = values_slot('validate', invalid_map_value)
  lu.assertNil(internal_value_value)
  lu.assertTrue(string.len(internal_value_message) > 0)

  local invalid_map_by_value <const> = {['score']=invalid_map_value}
  local value, message = map_slot('validate', invalid_map_by_value)
  lu.assertNil(value)
  lu.assertEquals(message, "map table value: " .. internal_value_message)

  -- TODO: formatting
end

function test_slot.test_optional_wrapper()
  -- internal slot works as expected
  local internal_slot <const> = dt.AnySlot
  local value, message = internal_slot('validate', nil)
  lu.assertNil(value)
  lu.assertEquals(message, "slot value must not be nil")

  -- outer slot is a valid Slot instance
  local outer_slot <const> = dt.Optional(internal_slot)
  lu.assertTrue(dt.Slot.is(outer_slot))

  -- outer slot validate works with nil
  local value, message = outer_slot('validate', nil)
  lu.assertNil(value)
  lu.assertNil(message)

  -- outer slot format works with nil
  local format_nil <const> = outer_slot('format', nil)
  lu.assertEquals(format_nil, "nil")

  -- outer slot uses internal slot for formatting
  local sample_value <const> = "Hello, world!"
  local format_inner <const> = internal_slot('format', sample_value)
  local format_outer <const> = outer_slot('format', sample_value)
  lu.assertEquals(format_inner, format_outer)
end

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
  lu.assertFalse(MutablePerson.freeze_instances)

  local FrozenPerson <const> = dt.DataTable({name=dt.StringSlot}, {freeze_instances=true})
  lu.assertTrue(FrozenPerson.freeze_instances)
end

function test_datatable_type.test_is_instance()
  local instance <const> = dt.DataTable{slot=dt.AnySlot}
  lu.assertTrue(dt.DataTable.is(instance))
  lu.assertFalse(dt.DataTable.is({}))
end

function test_datatable_type.test_slot_wrapper()
  local Mock <const> = dt.DataTable{name=dt.StringSlot}
  local instance <const> = Mock{name='alex'}

  local mock_slot <const> = dt.DataTableSlot(Mock)
  lu.assertTrue(dt.Slot.is(mock_slot))

  local value, message = mock_slot('validate', instance)
  lu.assertEquals(value, instance)
  lu.assertNil(message)

  local value, message = mock_slot('validate', 'obviously-not-a-slot')
  lu.assertNil(value)
  lu.assertStrContains(message, "value must be an instance of datatable: DataTableType: ")

  -- TODO: formatting
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
    height=dt.Optional(dt.NumberSlot),
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

  john_doe.height = nil
  lu.assertNil(john_doe.height)

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
  -- datatable with instances that are always frozen
  local FrozenPerson <const> = dt.DataTable({name=dt.StringSlot}, {freeze_instances=true})
  lu.assertTrue(FrozenPerson.freeze_instances)

  lu.assertErrorMsgContains(
    "DataTable type freeze_instances requires instances to also be frozen",
    FrozenPerson,
    {name='John Doe'},
    {frozen=false}
  )

  local john_doe <const> = FrozenPerson{name='John Doe'}

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
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    john_doe,
    'name',
    'test'
  )

  -- datatable with instances frozen on creation
  local Person <const> = dt.DataTable{name=dt.StringSlot}
  lu.assertFalse(Person.freeze_instances)

  local jane_doe <const> = Person({name='Jane Doe'}, {frozen=true})

  lu.assertErrorMsgContains(
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    jane_doe,
    'name',
    'test'
  )

  -- datatable with instances frozen on demand
  local billy_smith <const> = Person{name='Billy Smith'}
  lu.assertFalse(Person:is_frozen(billy_smith))

  Person:freeze(billy_smith)
  lu.assertTrue(Person:is_frozen(billy_smith))

  lu.assertErrorMsgContains(
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    billy_smith,
    'name',
    'test'
  )
end

function test_datatable.test_freezing_nested()
  local Point <const> = dt.DataTable{x=dt.IntegerSlot, y=dt.IntegerSlot}
  local Line <const> = dt.DataTable{
    a=dt.DataTableSlot(Point),
    b=dt.DataTableSlot(Point)
  }

  local instance <const> = Line{
    a=Point{x=0, y=0},
    b=Point{x=100, y=100}
  }

  instance.a = Point{x=-10, y=-10}
  instance.b.y = 75

  local returned_instance <const> = Line:freeze(instance)
  lu.assertEquals(returned_instance, instance)

  lu.assertErrorMsgContains(
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    'a',
    Point{x=0, y=0}
  )

  lu.assertErrorMsgContains(
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance.a,
    'x',
    10
  )

  lu.assertErrorMsgContains(
    "DataTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance.b,
    'y',
    10
  )
end

function test_datatable.test_validator()
  -- always validate on datatable instance mutation
  -- TODO: use flag to toggle this behavior
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

  -- validate datatable instance on demand
  -- XXX: not necessary if we always validate on mutation
  local Point <const> = dt.DataTable{x=dt.IntegerSlot, y=dt.IntegerSlot}
  local Vector <const> = dt.DataTable({
    from=dt.DataTableSlot(Point),
    to=dt.DataTableSlot(Point)
  }, {
    validator=(function (data)
      local from_normal = math.sqrt((data.from.x ^ 2) + (data.from.y ^ 2))
      local to_normal = math.sqrt((data.to.x ^ 2) + (data.to.y ^ 2))
      if from_normal > to_normal then
        return "vector is not pointing away from the origin"
      end
    end)
  })

  local sample_vector <const> = Vector{
    from=Point{x=10, y=10},
    to=Point{x=100, y=100}
  }

  local valid, message = Vector:validate(sample_vector)
  lu.assertTrue(valid)
  lu.assertNil(message)

  sample_vector.from.x = 1000
  sample_vector.from.y = 1000

  local valid, message = Vector:validate(sample_vector)
  local expected_message <const> = "vector is not pointing away from the origin"
  lu.assertFalse(valid)
  lu.assertEquals(message, expected_message)

  -- validate on freeze
  -- XXX: not necessary if we always validate on mutation
  lu.assertErrorMsgContains(
    "DataTable instance data is not valid: " .. expected_message,
    Vector.freeze,
    Vector,
    sample_vector
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

  lu.assertTrue(CountA:is(count_a))
  lu.assertTrue(CountB:is(count_b))

  lu.assertFalse(CountA:is(count_b))
  lu.assertFalse(CountB:is(count_a))

  lu.assertFalse(CountA:is(CountA))
  lu.assertFalse(CountA:is({}))
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
