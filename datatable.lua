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

local AnySlot <const> = Slot.create(function (value)
  if value == nil then
    return nil, "slot value must not be nil"
  end

  if type(value) == 'table' then
    return nil, "slot value must not be a table"
  end

  return value
end)

local BooleanSlot <const> = Slot.create(function (value)
  if type(value) == 'boolean' then
    return value
  else
    return nil, "slot value must be a boolean"
  end
end)

local StringSlot <const> = Slot.create(function (value)
  if type(value) == 'string' then
    return value
  else
    return nil, "slot value must be a string"
  end
end, function (value)
  return '"' .. tostring(value) .. '"'
end)

local NumberSlot <const> = Slot.create(function (value)
  if type(value) == 'number' then
    return value
  else
    return nil, "slot value must be a number"
  end
end)

local IntegerSlot <const> = Slot.create(function (value)
  if math.type(value) == 'integer' then
    return value
  else
    return nil, "slot value must be an integer"
  end
end)

local FloatSlot <const> = Slot.create(function (value)
  if math.type(value) == 'float' then
    return value
  else
    return nil, "slot value must be a float"
  end
end)

--[[
Slot Optional Wrapper
--]]

local function Optional(internal_slot)
  assert(Slot.is(internal_slot), "internal_slot value must be a Slot instance")

  return Slot.create(function (value)
    if value == nil then
      return nil
    end

    return internal_slot('validate', value)
  end, function (value)
    return internal_slot('format', value)
  end)
end

--[[
DataTable

A table with defined string keys pointing to corresponding slot values.
--]]

local datatable_type_metatable <const> = {}
local datatable_type_private <const> = setmetatable({}, {__mode='k'})

local datatable_instance_metatable <const> = {}
local datatable_instance_private <const> = setmetatable({}, {__mode='k'})

-- instance implementation
local datatable_instance_check <const> = function (value)
  local instance_private <const> = assert(
    datatable_instance_private[value],
    "DataTable instance not recognized: " .. tostring(value)
  )

  local datatable_private <const> = assert(
    datatable_type_private[instance_private.datatable],
    "DataTable type not recognized: " .. tostring(value)
  )

  return instance_private, datatable_private
end

local datatable_instance_internal_metatable <const> = {
  __name = 'DataTable',
  __metatable = datatable_instance_metatable,
  __index = function (self, key)
    local private <const>, datatable_private <const> = datatable_instance_check(self)
    local slot <const> = assert(datatable_private.slots[key], "DataTable slot not found: " .. tostring(key))

    return private.data[key]
  end,
  __newindex = function (self, key, value)
    local private <const>, datatable_private <const> = datatable_instance_check(self)
    local slot <const> = assert(datatable_private.slots[key], "DataTable slot not found: " .. tostring(key))
    assert(not private.frozen, "DataTable instance is frozen")

    local value, message = slot('validate', value)
    if message then
      error("DataTable slot '" .. key .. "': " .. message)
    end

    -- TODO: use a flag to toggle whether we should always run the datatable
    -- validator or not, we may want to delay that until later

    local previous_value <const> = private.data[key]
    private.data[key] = value

    local message = datatable_private.validator(private.data)
    if message ~= nil then
      private.data[key] = previous_value  -- XXX: is there a better way without a shallow copy of private.data?
      assert(type(message) == 'string', "DataTable validator function must return a string message")
      error("DataTable instance data is not valid: " .. message)
    end
  end,
  __pairs = function (self)
    local private <const>, datatable_private <const> = datatable_instance_check(self)

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
    for name, _ in pairs(datatable_private.slots) do
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
local datatable_type_is <const> = function (self, value)
  if getmetatable(value) ~= datatable_instance_metatable then
    return false
  end

  local instance_private <const>, _ = datatable_instance_check(value)
  return (instance_private.datatable == self)
end

local datatable_type_is_frozen <const> = function (self, instance)
  local instance_private <const>, _ = datatable_instance_check(instance)
  assert(instance_private.datatable == self, "DataTable type method used with incompatible type")

  return instance_private.frozen
end

local datatable_type_class_methods <const> = {
  ['is']=datatable_type_is,
  ['is_frozen']=datatable_type_is_frozen,
}

local datatable_type_internal_metatable <const> = {
  __name = 'DataTableType',
  __metatable = datatable_type_metatable,
  __index = function (self, key)
    local private <const> = assert(
      datatable_type_private[self],
      "DataTable type not recognized: " .. tostring(self)
    )

    -- datatable type slots
    if key == 'slots' then
      -- shallow copy to prevent mutation
      local slots <const> = {}
      for name, slot in pairs(private.slots) do
        slots[name] = slot
      end

      return slots
    -- datatable frozen flag
    elseif key == 'freeze_instances' then
      return private.freeze_instances
    -- class methods
    elseif datatable_type_class_methods[key] ~= nil then
      return datatable_type_class_methods[key]
    -- unknown key
    else
      return nil
    end
  end,
  __newindex = function (_, _, _)
    error("DataTable definition cannot be modified")
  end,
  __call = function (self, value_data, flag_data)
    local private <const> = assert(
      datatable_type_private[self],
      "DataTable type not recognized: " .. tostring(self)
    )
  
    local initial_data <const> = {}
    for name, slot in pairs(private.slots) do
      local value, message = slot('validate', value_data[name])
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

    local flags <const> = flag_data or {}
    if type(flags) ~= 'table' then
      error("DataTable instance flags must be a table")
    end

    local frozen <const> = flags['frozen']
    if frozen ~= nil then
      if type(frozen) ~= 'boolean' then
        error("DataTable instance frozen flag must be a boolean")
      end

      if private.freeze_instances and not frozen then
        error("DataTable type freeze_instances requires instances to also be frozen")
      end
    end

    local instance_frozen <const> = (frozen or private.freeze_instances)
    local instance <const> = {}
    datatable_instance_private[instance] = {
      datatable=self,
      data=initial_data,
      frozen=instance_frozen
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

    local freeze_instances <const> = (flag_data['freeze_instances'] or false)
    if type(freeze_instances) ~= 'boolean' then
      error("DataTable freeze_instances flag must be a boolean")
    end

    local validator <const> = (flag_data['validator'] or (function (_) return end))
    if type(validator) ~= 'function' then
      error("DataTable validator flag must be a function")
    end

    local slots <const> = {}
    for name, value in pairs(slot_data) do
      -- XXX: can this ever happen?
      if slots[name] then
        error("DataTable duplicate slot name: " .. tostring(name))
      end

      if Slot.is(value) then
        slots[name] = value
      elseif type(value) == 'table' then
        slots[name] = Slot.create(table.unpack(value))
      else
        error("DataTable invalid slot value: " .. tostring(value))
      end
    end

    local instance <const> = {}
    datatable_type_private[instance] = {
      slots=slots,
      freeze_instances=freeze_instances,
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
DataTable Slot Wrapper
--]]

local function DataTableSlot(table_type)
  assert(DataTable.is(table_type), "table_type must be a DataTable type instance")

  return Slot.create(function (value)
    if table_type:is(value) then
      return value
    end

    return nil, "value must be an instance of datatable: " .. tostring(table_type)
  end, function (value)
    return tostring(table_type)
  end)
end

--[[
ArrayTable

A table with contiguous integer keys and a slot enforced values.
--]]

local arraytable_type_metatable <const> = {}
local arraytable_type_private <const> = setmetatable({}, {__mode='k'})

local arraytable_instance_metatable <const> = {}
local arraytable_instance_private <const> = setmetatable({}, {__mode='k'})

-- instance implementation
local arraytable_instance_check <const> = function (value)
  local instance_private <const> = assert(
    arraytable_instance_private[value],
    "ArrayTable instance not recognized: " .. tostring(value)
  )

  local arraytable_private <const> = assert(
    arraytable_type_private[instance_private.arraytable],
    "ArrayTable type not recognized: " .. tostring(value)
  )

  return instance_private, arraytable_private
end

local arraytable_instance_internal_metatable <const> = {
  __name = 'ArrayTable',
  __metatable = arraytable_instance_metatable,
  __len = function (self)
    local private <const>, _ = arraytable_instance_check(self)

    return #private.data
  end,
  __index = function (self, key)
    local private <const>, _ = arraytable_instance_check(self)

    if math.type(key) ~= 'integer' then
      error("ArrayTable index must be an integer: " .. tostring(key))
    end

    return private.data[key]
  end,
  __newindex = function (self, key, value)
    local private <const>, arraytable_private <const> = arraytable_instance_check(self)
    assert(not private.frozen, "ArrayTable instance is frozen")

    if math.type(key) ~= 'integer' then
      error("ArrayTable index must be an integer: " .. tostring(key))
    end

    local value, message = arraytable_private.value_slot('validate', value)
    if message then
      error("ArrayTable index " .. tostring(key) .. ": " .. message)
    end

    -- TODO: use a flag to toggle whether we should always run the arraytable
    -- validator or not, we may want to delay that until later

    local previous_value <const> = private.data[key]
    private.data[key] = value

    -- validate array indices are contiguous
    local key_count = 0
    for _, _ in ipairs(private.data) do
      key_count = key_count + 1
    end

    if key_count ~= #private.data then
      private.data[key] = previous_value
      error("ArrayTable indices must be contiguous")
    end

    -- validate new array data
    local message = arraytable_private.validator(private.data)
    if message ~= nil then
      private.data[key] = previous_value
      assert(type(message) == 'string', "ArrayTable validator function must return a string message")
      error("ArrayTable instance data is not valid: " .. message)
    end
  end,
  __pairs = function (self)
    local private <const>, _ = arraytable_instance_check(self)

    -- for loops: https://www.lua.org/manual/5.4/manual.html#3.3.5
    local function iterate(data, index) -- state variable, initial or previous control value
      index = index + 1
      local value <const> = data[index]

      if value == nil then
        return
      end

      return index, value -- control value, remaining loop values
    end

    -- iterator function, state variable, initial control value, closing variable
    return iterate, private.data, 0, nil
  end,
  __gc = function (self)
    arraytable_instance_private[self] = nil
  end
}

-- type implementation
local arraytable_type_is <const> = function (self, value)
  if getmetatable(value) ~= arraytable_instance_metatable then
    return false
  end

  local instance_private <const>, _ = arraytable_instance_check(value)
  return (instance_private.arraytable == self)
end

local arraytable_type_is_frozen <const> = function (self, instance)
  local instance_private <const>, _ = arraytable_instance_check(instance)
  assert(instance_private.arraytable == self, "ArrayTable type method used with incompatible type")

  return instance_private.frozen
end

local arraytable_type_class_methods <const> = {
  ['is']=arraytable_type_is,
  ['is_frozen']=arraytable_type_is_frozen,
}

local arraytable_type_internal_metatable <const> = {
  __name = 'ArrayTableType',
  __metatable = arraytable_type_metatable,
  __index = function (self, key)
    local private <const> = assert(
      arraytable_type_private[self],
      "ArrayTable type not recognized: " .. tostring(self)
    )

    -- value slot
    if key == 'value_slot' then
      return private.value_slot
    -- arraytable frozen flag
    elseif key == 'freeze_instances' then
      return private.freeze_instances
    -- class methods
    elseif arraytable_type_class_methods[key] ~= nil then
      return arraytable_type_class_methods[key]
    -- unknown key
    else
      return nil
    end
  end,
  __newindex = function (_, _, _)
    error("ArrayTable definition cannot be modified")
  end,
  __call = function (self, value_data, flag_data)
    local private <const> = assert(
      arraytable_type_private[self],
      "ArrayTable type not recognized: " .. tostring(self)
    )

    local key_count = 0
    local initial_data <const> = {}
    for index, value in ipairs(value_data) do
      local value, message = private.value_slot('validate', value)
      if message then
        error("ArrayTable index " .. tostring(index) .. ": " .. message)
      end

      key_count = key_count + 1
      initial_data[index] = value
    end

    if key_count ~= #value_data then
      error("ArrayTable indices must be contiguous")
    end

    local message <const> = private.validator(initial_data)
    if message ~= nil then
      assert(type(message) == 'string', "ArrayTable validator function must return a string message")
      error("ArrayTable instance data is not valid: " .. message)
    end

    local flags <const> = flag_data or {}
    if type(flags) ~= 'table' then
      error("ArrayTable instance flags must be a table")
    end

    local frozen <const> = flags['frozen']
    if frozen ~= nil then
      if type(frozen) ~= 'boolean' then
        error("ArrayTable instance frozen flag must be a boolean")
      end

      if private.freeze_instances and not frozen then
        error("ArrayTable type freeze_instances requires instances to also be frozen")
      end
    end

    local instance_frozen <const> = (frozen or private.freeze_instances)
    local instance <const> = {}
    arraytable_instance_private[instance] = {
      arraytable=self,
      data=initial_data,
      frozen=instance_frozen
    }

    return setmetatable(instance, arraytable_instance_internal_metatable)
  end,
  __gc = function (self)
    arraytable_type_private[self] = nil
  end
}

-- public interface
local ArrayTable <const> = setmetatable({
  create = function (config_data)
    if type(config_data) ~= 'table' then
      error("ArrayTable config must be a table")
    end

    local value_slot <const> = (config_data['value_slot'] or AnySlot)
    if not Slot.is(value_slot) then
      error("ArrayTable value_slot must be a Slot instance")
    end

    local freeze_instances <const> = (config_data['freeze_instances'] or false)
    if type(freeze_instances) ~= 'boolean' then
      error("ArrayTable freeze_instances flag must be a boolean")
    end

    local validator <const> = (config_data['validator'] or (function (_) return end))
    if type(validator) ~= 'function' then
      error("ArrayTable validator flag must be a function")
    end

    local instance <const> = {}
    arraytable_type_private[instance] = {
      value_slot=value_slot,
      freeze_instances=freeze_instances,
      validator=validator
    }

    return setmetatable(instance, arraytable_type_internal_metatable)
  end,
  is = function (value)
    return (getmetatable(value) == arraytable_type_metatable)
  end
}, {
  __call = function (self, ...)
    return self.create(...)
  end
})

--[[
ArrayTable Slot Wrapper
--]]

local function ArrayTableSlot(table_type)
  assert(ArrayTable.is(table_type), "table_type must be a ArrayTable type instance")

  return Slot.create(function (value)
    if table_type:is(value) then
      return value
    end

    return nil, "value must be an instance of arraytable: " .. tostring(table_type)
  end, function (value)
    return tostring(table_type)
  end)
end

--[[
Generic Internal Helpers
--]]

local generic_table_is_instance <const> = function (value)
  local mt <const> = getmetatable(value)
  return (
    mt == datatable_instance_metatable or
    mt == arraytable_instance_metatable
  )
end

local generic_table_is_type <const> = function (value)
  local mt <const> = getmetatable(value)
  return (
    mt == datatable_type_metatable or
    mt == arraytable_type_metatable
  )
end

-- return a shallow copy of table instances contained by the provided instance
-- note: this only checks one level deep in order to avoid searching
local generic_table_nested_instances = function (instance)
  local values <const> = {}

  if getmetatable(instance) == datatable_instance_metatable then
    local private <const> = assert(datatable_instance_private[instance])

    for _, value in pairs(private.data) do
      if generic_table_is_instance(value) then
        table.insert(values, value)
      end
    end
  elseif getmetatable(instance) == arraytable_instance_metatable then
    local private <const> = assert(arraytable_instance_private[instance])

    for _, value in ipairs(private.data) do
      if generic_table_is_instance(value) then
        table.insert(values, value)
      end
    end
  else
    error("invalid table instance type")
  end

  return values
end

--[[
Table Validation
--]]

local generic_table_type_validate <const> = function (root_instance, recurse)
  -- freeze the provided instance
  local function _validate_instance(instance)
    local mt <const> = getmetatable(instance)
    if mt == datatable_instance_metatable then
      local instance_private <const> = assert(datatable_instance_private[instance])
      local datatable_private <const> = assert(datatable_type_private[instance_private.datatable])

      local message <const> = datatable_private.validator(instance_private.data)
      if message ~= nil then
        -- TODO: improve the error to specify which nested instance failed validation
        assert(type(message) == 'string', "DataTable validator function must return a string message")
        return false, message
      end
    elseif mt == arraytable_instance_metatable then
      local instance_private <const> = assert(arraytable_instance_private[instance])
      local arraytable_private <const> = assert(arraytable_type_private[instance_private.arraytable])

      local message <const> = arraytable_private.validator(instance_private.data)
      if message ~= nil then
        -- TODO: improve the error to specify which nested instance failed validation
        assert(type(message) == 'string', "ArrayTable validator function must return a string message")
        return false, message
      end
    else
      error("invalid table instance type")
    end

    return true, nil
  end

  -- use breadth-first search from the root instance to find all nested tables
  local instances <const> = {root_instance}
  while #instances > 0 do
    local instance <const> = table.remove(instances, 1)
    local valid <const>, message <const> = _validate_instance(instance)
    if not valid then
      return false, message
    end

    local nested_instances <const> = generic_table_nested_instances(instance)
    for _, nested_instance in ipairs(nested_instances) do
      table.insert(instances, nested_instance)
    end
  end

  return true, nil
end

local datatable_type_validate <const> = function (self, instance)
  local instance_private <const>, _ = datatable_instance_check(instance)
  assert(instance_private.datatable == self, "DataTable type method used with incompatible type")

  return generic_table_type_validate(instance)
end

local arraytable_type_validate <const> = function (self, instance)
  local instance_private <const>, _ = arraytable_instance_check(instance)
  assert(instance_private.arraytable == self, "ArrayTable type method used with incompatible type")

  return generic_table_type_validate(instance)
end

datatable_type_class_methods['validate'] = datatable_type_validate
arraytable_type_class_methods['validate'] = arraytable_type_validate

--[[
Table Freezing
--]]

local generic_table_type_freeze <const> = function (root_instance)
  -- freeze the provided instance
  local function _freeze_instance(instance)
    local mt <const> = getmetatable(instance)
    if mt == datatable_instance_metatable then
      local instance_private <const> = assert(datatable_instance_private[instance])
      local datatable_private <const> = assert(datatable_type_private[instance_private.datatable])

      local message <const> = datatable_private.validator(instance_private.data)
      if message ~= nil then
        -- TODO: improve the error to specify which nested instance failed validation
        assert(type(message) == 'string', "DataTable validator function must return a string message")
        error("DataTable instance data is not valid: " .. message)
      end

      instance_private.frozen = true
    elseif mt == arraytable_instance_metatable then
      local instance_private <const> = assert(arraytable_instance_private[instance])
      local arraytable_private <const> = assert(arraytable_type_private[instance_private.arraytable])

      local message <const> = arraytable_private.validator(instance_private.data)
      if message ~= nil then
        -- TODO: improve the error to specify which nested instance failed validation
        assert(type(message) == 'string', "ArrayTable validator function must return a string message")
        error("ArrayTable instance data is not valid: " .. message)
      end

      instance_private.frozen = true
    else
      error("invalid table instance type")
    end
  end

  -- use breadth-first search from the root instance to find all nested tables
  local instances <const> = {root_instance}
  while #instances > 0 do
    local instance <const> = table.remove(instances, 1)
    _freeze_instance(instance)

    local nested_instances <const> = generic_table_nested_instances(instance)
    for _, nested_instance in ipairs(nested_instances) do
      table.insert(instances, nested_instance)
    end
  end
end

local datatable_type_freeze <const> = function (self, instance)
  local instance_private <const>, _ = datatable_instance_check(instance)
  assert(instance_private.datatable == self, "DataTable type method used with incompatible type")

  -- use shared generic implementation
  generic_table_type_freeze(instance)

  -- return the datatable instance to make chaining and returning it easy
  return instance
end

local arraytable_type_freeze <const> = function (self, instance)
  local instance_private <const>, _ = arraytable_instance_check(instance)
  assert(instance_private.arraytable == self, "ArrayTable type method used with incompatible type")

  -- use shared generic implementation
  generic_table_type_freeze(instance)

  -- return the datatable instance to make chaining and returning it easy
  return instance
end

datatable_type_class_methods['freeze'] = datatable_type_freeze
arraytable_type_class_methods['freeze'] = arraytable_type_freeze

--[[
Module Interface
--]]

local module = {
  -- slot
  Slot=Slot,

  -- default slots
  AnySlot=AnySlot,
  BooleanSlot=BooleanSlot,
  StringSlot=StringSlot,
  NumberSlot=NumberSlot,
  IntegerSlot=IntegerSlot,
  FloatSlot=FloatSlot,

  -- slot wrappers
  Optional=Optional,

  -- datatable
  DataTable=DataTable,
  DataTableSlot=DataTableSlot,

  -- arraytable
  ArrayTable=ArrayTable,
  ArrayTableSlot=ArrayTableSlot,
}

if os.getenv('LUA_DATATABLE_LEAK_INTERNALS') == 'TRUE' then
  -- leak internal variables and methods in order to unit test them from outside
  -- of this module but at least we can use an obvious environment variable
  -- and issue a warning to prevent someone from relying on this
  warn("lua-enum: LUA_DATATABLE_LEAK_INTERNALS is set and internals are exported in module")

  -- stating the obvious but these are not part of the public interface
  module['slot_metatable'] = slot_metatable
  module['slot_private'] = slot_private

  module['datatable_type_metatable'] = datatable_type_metatable
  module['datatable_type_private'] = datatable_type_private
  module['datatable_instance_metatable'] = datatable_instance_metatable
  module['datatable_instance_private'] = datatable_instance_private

  module['arraytable_type_metatable'] = arraytable_type_metatable
  module['arraytable_type_private'] = arraytable_type_private
  module['arraytable_instance_metatable'] = arraytable_instance_metatable
  module['arraytable_instance_private'] = arraytable_instance_private

  module['generic_table_is_instance'] = generic_table_is_instance
  module['generic_table_is_type'] = generic_table_is_type
  module['generic_table_nested_instances'] = generic_table_nested_instances
end

return module
