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
Slot Unit Tests
--]]

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

--[[
DataTable Type Unit Tests
--]]

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
  }

  local expected_slot_names <const> = {
    ['alive']=true,
    ['name']=true,
    ['age']=true,
    ['height']=true,
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

--[[
DataTable Instance Unit Tests
--]]

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
  }

  local john_doe <const> = Person{
    alive=true,
    name='John Doe',
    age=18,
    height=80.5,
  }

  lu.assertEquals(john_doe.alive, true)
  lu.assertEquals(john_doe.name, 'John Doe')
  lu.assertEquals(john_doe.age, 18)
  lu.assertEquals(john_doe.height, 80.5)

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
    a=dt.TableSlot(Point),
    b=dt.TableSlot(Point)
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
    from=dt.TableSlot(Point),
    to=dt.TableSlot(Point)
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
  }

  local data <const> = {
    alive=true,
    name='John Doe',
    age=18,
    height=80.5,
  }

  local john_doe <const> = Person(data)

  for key, value in pairs(john_doe) do
    lu.assertEquals(data[key], value)
    data[key] = nil
  end

  lu.assertEquals(countTableKeys(data), 0)
end

function test_datatable.test_is_instance()
  local MockA <const> = dt.DataTable{count=dt.IntegerSlot}
  local instance_a <const> = MockA{count=0}

  local MockB <const> = dt.DataTable{count=dt.IntegerSlot}
  local instance_b <const> = MockB{count=0}

  lu.assertTrue(MockA:is(instance_a))
  lu.assertTrue(MockB:is(instance_b))

  lu.assertFalse(MockA:is(instance_b))
  lu.assertFalse(MockB:is(instance_a))

  lu.assertFalse(MockA:is(MockA))
  lu.assertFalse(MockA:is({}))
end

--[[
ArrayTable Type Unit Tests
--]]

test_arraytable_type = {}

function test_arraytable_type.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.arraytable_type_private)

  local instance = dt.ArrayTable{}
  lu.assertEquals(countTableKeys(dt.arraytable_type_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.arraytable_type_private), initial_count)
end

function test_arraytable_type.test_frozen()
  local MutableArrayTable <const> = dt.ArrayTable{}
  lu.assertFalse(MutableArrayTable.freeze_instances)

  local FrozenArrayTable <const> = dt.ArrayTable{freeze_instances=true}
  lu.assertTrue(FrozenArrayTable.freeze_instances)
end

function test_arraytable_type.test_is_instance()
  local instance <const> = dt.ArrayTable{}
  lu.assertTrue(dt.ArrayTable.is(instance))
  lu.assertFalse(dt.ArrayTable.is({}))
end

--[[
ArrayTable Instance Unit Tests
--]]

test_arraytable = {}

function test_arraytable.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.arraytable_instance_private)

  local Mock <const> = dt.ArrayTable{}
  local instance = Mock{}
  lu.assertEquals(countTableKeys(dt.arraytable_instance_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.arraytable_instance_private), initial_count)
end

function test_arraytable.test_custom_slot()
  local PersonAges <const> = dt.ArrayTable{
    value_slot=dt.Slot(function (value)
      if type(value) ~= 'number' or value <= 0 then
        return nil, "custom_value_slot_error"
      end

      return value
    end)
  }

  local ages <const> = PersonAges{1, 2}
  lu.assertEquals(#ages, 2)
  lu.assertEquals(ages[1], 1)
  lu.assertEquals(ages[2], 2)

  ages[1] = 29
  lu.assertEquals(ages[1], 29)

  lu.assertErrorMsgContains(
    "custom_value_slot_error",
    function (i, k, v)
      i[k] = v
    end,
    ages,
    2,
    -20
  )
end

function test_arraytable.test_indices()
  local Integers <const> = dt.ArrayTable{value_slot=dt.IntegerSlot}

  -- validate indices on creation
  lu.assertErrorMsgContains(
    "ArrayTable indices must be contiguous",
    Integers,
    {[1]=10, [3]=20}
  )

  lu.assertErrorMsgContains(
    "ArrayTable indices must be positive",
    Integers,
    {[-5]=10, [3]=20}
  )

  -- validate indices on mutation
  local instance <const> = Integers{}
  table.insert(instance, 10)
  table.insert(instance, 20)

  lu.assertEquals(#instance, 2)
  lu.assertEquals(instance[1], 10)
  lu.assertEquals(instance[2], 20)

  table.remove(instance, 1)
  lu.assertEquals(#instance, 1)
  lu.assertEquals(instance[1], 20)

  lu.assertErrorMsgContains(
    "ArrayTable indices must be contiguous",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    4,
    100
  )

  lu.assertErrorMsgContains(
    "ArrayTable index must be positive: ",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    -5,
    100
  )

  table.insert(instance, 40)
  table.insert(instance, 50)
  lu.assertEquals(#instance, 3)

  lu.assertErrorMsgContains(
    "ArrayTable indices must be contiguous",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    2,
    nil
  )
end

function test_arraytable.test_frozen()
  -- arraytable with isntances that are always frozen
  local FrozenIntegers <const> = dt.ArrayTable{value_slot=dt.IntegerSlot, freeze_instances=true}
  lu.assertTrue(FrozenIntegers.freeze_instances)

  lu.assertErrorMsgContains(
    "ArrayTable type freeze_instances requires instances to also be frozen",
    FrozenIntegers,
    {10, 20, 30},
    {frozen=false}
  )

  local frozen_numbers <const> = FrozenIntegers{2, 42}

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    frozen_numbers,
    3,
    100
  )

  -- arraytable with instances frozen on creation
  local Integers <const> = dt.ArrayTable{value_slot=dt.IntegerSlot}
  lu.assertFalse(Integers.freeze_instances)

  local more_numbers <const> = Integers({2, 42}, {frozen=true})

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    more_numbers,
    3,
    100
  )

  -- arraytable with instances frozen on demand
  local scratch_numbers <const> = Integers{1, 1, 2}
  lu.assertFalse(Integers:is_frozen(scratch_numbers))

  Integers:freeze(scratch_numbers)
  lu.assertTrue(Integers:is_frozen(scratch_numbers))

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    scratch_numbers,
    3,
    100
  )
end

function test_arraytable.test_freezing_nested()
  local Integers <const> = dt.ArrayTable{value_slot=dt.IntegerSlot}
  local Points <const> = dt.ArrayTable{value_slot=dt.TableSlot(Integers)}

  local instance <const> = Points{
    Integers{1, 2, 3},
    Integers{4, 5, 6}
  }

  instance[1] = Integers{7, 8, 9}
  instance[2][1] = 10

  local returned_instance <const> = Points:freeze(instance)
  lu.assertEquals(returned_instance, instance)

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    1,
    Integers{}
  )

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance[1],
    1,
    100
  )

  lu.assertErrorMsgContains(
    "ArrayTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance[2],
    1,
    100
  )
end

function test_arraytable.test_validator()
  -- always validate on arraytable instance mutation
  -- TODO: use flag to toggle this behavior
  local EvenIntegers <const> = dt.ArrayTable{
    value_slot=dt.IntegerSlot,
    validator=(function (data)
      for _, value in ipairs(data) do
        if value % 2 ~= 0 then
          return "Values must be even integers"
        end
      end
    end)
  }

  local instance <const> = EvenIntegers{2, 4, 6}
  instance[1] = 10
  instance[2] = 12

  lu.assertErrorMsgContains(
    "Values must be even integers",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    4,
    3
  )

  lu.assertErrorMsgContains(
    "Values must be even integers",
    EvenIntegers,
    {7, 8}
  )

  -- TODO: validate arraytable instance on demand
  -- XXX: not necessary if we always validate on mutation

  -- TODO: validate on freeze
  -- XXX: not necessary if we always validate on mutation
end

function test_arraytable.test_enumeration()
  local Integers <const> = dt.ArrayTable{value_slot=dt.IntegerSlot}
  local data <const> = {5, 3, 10, 42, 17}
  local instance <const> = Integers(data)

  for index, value in ipairs(instance) do
    lu.assertEquals(data[index], value)
    data[index] = nil
  end

  lu.assertEquals(countTableKeys(data), 0)
end

function test_arraytable.test_is_instance()
  local MockA <const> = dt.ArrayTable{}
  local instance_a <const> = MockA{}

  local MockB <const> = dt.ArrayTable{}
  local instance_b <const> = MockB{}

  lu.assertTrue(MockA:is(instance_a))
  lu.assertTrue(MockB:is(instance_b))

  lu.assertFalse(MockA:is(instance_b))
  lu.assertFalse(MockB:is(instance_a))

  lu.assertFalse(MockA:is(MockA))
  lu.assertFalse(MockA:is({}))
end

--[[
MapTable Type Unit Tests
--]]

test_maptable_type = {}

function test_maptable_type.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.maptable_type_private)

  local instance = dt.MapTable{}
  lu.assertEquals(countTableKeys(dt.maptable_type_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.maptable_type_private), initial_count)
end

-- XXX: custom slots
-- XXX: default slots

function test_maptable_type.test_frozen()
  local MutableMap <const> = dt.MapTable{}
  lu.assertFalse(MutableMap.freeze_instances)

  local FrozenMap <const> = dt.MapTable{freeze_instances=true}
  lu.assertTrue(FrozenMap.freeze_instances)
end

function test_datatable_type.test_is_instance()
  local instance <const> = dt.MapTable{}
  lu.assertTrue(dt.MapTable.is(instance))
  lu.assertFalse(dt.MapTable.is({}))
end

--[[
MapTable Instance Unit Tests
--]]

test_maptable = {}

function test_maptable.test_lifecycle()
  collectgarbage('collect')
  local initial_count = countTableKeys(dt.maptable_instance_private)

  local Mock <const> = dt.MapTable{}
  local instance = Mock{}
  lu.assertEquals(countTableKeys(dt.maptable_instance_private), initial_count + 1)

  instance = nil
  collectgarbage('collect')
  lu.assertEquals(countTableKeys(dt.maptable_instance_private), initial_count)
end

function test_maptable.test_custom_slots()
  local CustomMap <const> = dt.MapTable{
    key_slot=dt.Slot(function (value)
      if type(value) ~= 'string' or #value == 0 then
        return nil, "custom_key_slot_error"
      end

      return value
    end),
    value_slot=dt.Slot(function (value)
      if type(value) ~= 'number' or value <= 0 then
        return nil, "custom_value_slot_error"
      end

      return value
    end)
  }

  local instance <const> = CustomMap{['foo']=10, ['bar']=20}
  lu.assertEquals(instance['foo'], 10)
  lu.assertEquals(instance['bar'], 20)

  instance['foo'] = 30
  lu.assertEquals(instance['foo'], 30)

  lu.assertErrorMsgContains(
    "custom_key_slot_error",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    '',
    100
  )

  lu.assertErrorMsgContains(
    "custom_value_slot_error",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    'test',
    -50
  )
end

-- TODO: test_frozen

function test_maptable.test_freezing_nested()
  local Bookmarks <const> = dt.MapTable{
    key_slot=dt.StringSlot,
    value_slot=dt.StringSlot
  }

  local UserBookmarks <const> = dt.MapTable{
    key_slot=dt.StringSlot,
    value_slot=dt.TableSlot(Bookmarks)
  }

  local instance <const> = UserBookmarks{
    ['bob']=Bookmarks{['search']='duckduckgo.com'},
    ['alice']=Bookmarks{['search']='kagi.com'},
  }

  instance.bob.home = 'example.com'
  instance.bill = Bookmarks{['search']='bing.com'}

  local returned_instance <const> = UserBookmarks:freeze(instance)
  lu.assertEquals(returned_instance, instance)

  lu.assertErrorMsgContains(
    "MapTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    'bob',
    UserBookmarks{}
  )

  lu.assertErrorMsgContains(
    "MapTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance.bob,
    'search',
    'google.com'
  )

  lu.assertErrorMsgContains(
    "MapTable instance is frozen",
    function (i, k, v)
      i[k] = v
    end,
    instance.alice,
    'search',
    'google.com'
  )
end

function test_maptable.test_validator()
  -- always validate on maptable instance mutation
  -- TODO: use flag to toggle this behavior
  local Bookmarks <const> = dt.MapTable{
    key_slot=dt.StringSlot,
    value_slot=dt.StringSlot,
    validator=(function (data)
      if countTableKeys(data) > 2 then
        return "Bookmarks table size too large"
      end
    end)
  }

  local instance <const> = Bookmarks{
    ['foo']='example.com',
    ['bar']='example.com',
  }

  lu.assertErrorMsgContains(
    "Bookmarks table size too large",
    function (i, k, v)
      i[k] = v
    end,
    instance,
    'baz',
    'example.com'
  )

  -- TODO: validate maptable instance on demand
  -- TODO: validate maptable instance on freeze
end

function test_maptable.test_data_pairs_enumeration()
  local NamedNumbers <const> = dt.MapTable{
    key_slot=dt.StringSlot,
    value_slot=dt.IntegerSlot,
  }

  local data <const> = {
    ['base_binary']=2,
    ['answer_to_everything']=42,
    ['maximum_percent']=100,
  }

  local named_numbers <const> = NamedNumbers(data)

  for key, value in pairs(named_numbers) do
    lu.assertEquals(data[key], value)
    data[key] = nil
  end

  lu.assertEquals(countTableKeys(data), 0)
end

function test_maptable.test_is_instance()
  local MockA <const> = dt.MapTable{}
  local instance_a <const> = MockA{}

  local MockB <const> = dt.MapTable{}
  local instance_b <const> = MockB{}

  lu.assertTrue(MockA:is(instance_a))
  lu.assertTrue(MockB:is(instance_b))

  lu.assertFalse(MockA:is(instance_b))
  lu.assertFalse(MockB:is(instance_a))

  lu.assertFalse(MockA:is(MockA))
  lu.assertFalse(MockA:is({}))
end

--[[
Table Slot Wrapper Unit Tests
--]]

test_slot_wrapper = {}

function test_slot_wrapper.test_datatable_slot()
  local Mock <const> = dt.DataTable{name=dt.StringSlot}
  local instance <const> = Mock{name='alex'}

  local mock_slot <const> = dt.TableSlot(Mock)
  lu.assertTrue(dt.Slot.is(mock_slot))

  local value, message = mock_slot('validate', instance)
  lu.assertEquals(value, instance)
  lu.assertNil(message)

  local value, message = mock_slot('validate', 'obviously-not-a-slot')
  lu.assertNil(value)
  lu.assertStrContains(message, "value must be an instance of table type: " .. tostring(Mock))

  -- TODO: formatting
end

function test_slot_wrapper.test_arraytable_slot()
  local Mock <const> = dt.ArrayTable{}
  local instance <const> = Mock{}

  local mock_slot <const> = dt.TableSlot(Mock)
  lu.assertTrue(dt.Slot.is(mock_slot))

  local value, message = mock_slot('validate', instance)
  lu.assertEquals(value, instance)
  lu.assertNil(message)

  local value, message = mock_slot('validate', 'obviously-not-a-slot')
  lu.assertNil(value)
  lu.assertStrContains(message, "value must be an instance of table type: " .. tostring(Mock))

  -- TODO: formatting
end

function test_slot_wrapper.test_maptable_slot()
  local Mock <const> = dt.MapTable{}
  local instance <const> = Mock{1, 2, 3}

  local mock_slot <const> = dt.TableSlot(Mock)
  lu.assertTrue(dt.Slot.is(mock_slot))

  local value, message = mock_slot('validate', instance)
  lu.assertEquals(value, instance)
  lu.assertNil(message)

  local value, message = mock_slot('validate', 'obviously-not-a-slot')
  lu.assertNil(value)
  lu.assertStrContains(message, "value must be an instance of table type: " .. tostring(Mock))

  -- TODO: formatting
end

-- TODO: test validation for table slot wrapper

--[[
Module Interface
--]]

return {
  test_slot=test_slot,
  test_datatable_type=test_datatable_type,
  test_datatable=test_datatable,
  test_arraytable_type=test_arraytable_type,
  test_arraytable=test_arraytable,
  test_maptable_type=test_maptable_type,
  test_maptable=test_maptable,
  test_slot_wrapper=test_slot_wrapper,
}
