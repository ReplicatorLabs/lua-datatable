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
  else
    return value
  end
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

local TableSlot <const> = Slot.create(function (value)
  if type(value) == 'table' then
    return value
  else
    return nil, "slot value must be a table"
  end
end, function (value)
  return "{" .. tostring(value) .. "}"
end)

--[[
Slot Factories
--]]

local function create_array_table_slot(constraints)
  local min_key_count <const> = constraints['min_keys'] or 0
  assert(math.type(min_key_count) == 'integer', "min_keys constraint must be an integer")

  local max_key_count <const> = constraints['max_keys'] or nil
  if max_key_count then
    assert(math.type(max_key_count) == 'integer', "max_keys constraint must be an integer or nil")
    if max_key_count < min_key_count then
      error("min_keys constraint must be less than or equal to max_keys constraint")
    end
  end

  local contiguous <const> = constraints['contiguous'] or true
  assert(type(contiguous) == 'boolean', "contiguous constraint must be a boolean")

  local value_slot <const> = constraints['values'] or AnySlot
  assert(Slot.is(value_slot), "values constraint must be a Slot instance")

  return Slot.create(function (value)
    if type(value) ~= 'table' then
      return nil, "value must be a table"
    end

    local key_count = 0
    for entry_key, entry_value in pairs(value) do
      key_count = key_count + 1

      if math.type(entry_key) ~= 'integer' then
        return nil, "array table keys must be integers"
      end

      local _, message = value_slot('validate', entry_value)
      if message then
        return nil, "array table value invalid: " .. message
      end
    end

    if key_count < min_key_count then
      return nil, "array must contain at least " .. tostring(min_key_count) .. " keys"
    end

    if max_key_count and key_count > max_key_count then
      return nil, "array must contain no more than " .. tostring(max_key_count) .. " keys"
    end

    if contiguous and key_count ~= #value then
      return nil, "array must be contiguous"
    end

    return value
  end, function (value)
    local formatted_entries <const> = {}

    if contiguous then
      for index, entry_value in ipairs(value) do
        table.insert(formatted_entries, value_slot('format', entry_value))
      end
    else
      for index, entry_value in pairs(value) do
        local formatted_key <const> = "[" .. tostring(index) .. "]"
        local formatted_value <const> = value_slot('format', entry_value)
        table.insert(formatted_entries, formatted_key .. "=" .. formatted_value)
      end
    end

    return ("{" .. table.concat(formatted_entries, ",") .. "}")
  end)
end

local function create_map_table_slot(constraints)
  -- XXX: consider supporting min_keys and max_keys like above

  local key_slot <const> = constraints['keys'] or AnySlot
  assert(Slot.is(key_slot), "keys constraint must be a Slot instance")

  local value_slot <const> = constraints['values'] or AnySlot
  assert(Slot.is(value_slot), "values contraint must be a Slot instance")

  return Slot.create(function (value)
    if type(value) ~= 'table' then
      return nil, "value must be a table"
    end

    for entry_key, entry_value in pairs(value) do
      local _, message = key_slot('validate', entry_key)
      if message then
        return nil, "map table key: " .. message
      end

      local _, message = value_slot('validate', entry_value)
      if message then
        return nil, "map table value: " .. message
      end
    end

    return value
  end, function (value)
    local formatted_entries <const> = {}
    for entry_key, entry_value in pairs(value) do
      local formatted_key <const> = "[" .. key_slot('format', entry_key) .. "]"
      local formatted_value <const> = value_slot('format', entry_value)
      table.insert(formatted_entries, formatted_key .. "=" .. formatted_value)
    end

    return ("{" .. table.concat(formatted_entries, ",") .. "}")
  end)
end

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
    assert(not private.frozen, "DataTable instance is frozen")

    local value, message = slot('validate', value)
    if message then
      error("DataTable slot '" .. key .. "': " .. message)
    end

    -- TODO: use a flag to toggle whether we should always run the datatable
    -- validator or not, we may want to delay that until later

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
local datatable_type_is <const> = function (self, value)
  if getmetatable(value) ~= datatable_instance_metatable then
    return false
  end

  local private <const> = assert(
    datatable_instance_private[value],
    "DataTable instance not recognized: " .. tostring(value)
  )

  return (private.datatable == self)
end

local datatable_type_freeze <const> = function (self, instance)
  local private <const> = assert(
    datatable_instance_private[instance],
    "DataTable instance not recognized: " .. tostring(instance)
  )

  assert(private.datatable == self, "DataTable type method used with incompatible type")
  local datatable <const> = assert(
    datatable_type_private[private.datatable],
    "DataTable type not recognized: " .. tostring(private.datatable)
  )

  -- validate the instance first
  local message <const> = datatable.validator(private.data)
  if message ~= nil then
    assert(type(message) == 'string', "DataTable validator function must return a string message")
    error("DataTable instance data is not valid: " .. message)
  end

  -- use breadth-first search starting from this datatable instance to find
  -- all the nested datatables and freeze them
  local instances <const> = {private}
  while #instances > 0 do
    local instance_private <const> = table.remove(instances, 1)
    instance_private.frozen = true

    for key, value in pairs(instance_private.data) do
      if getmetatable(value) == datatable_instance_metatable then
        local instance_private <const> = datatable_instance_private[value]
        table.insert(instances, instance_private)
      end
    end
  end

  -- return the datatable instance to make chaining and returning it easy
  return instance
end

local datatable_type_is_frozen <const> = function (self, instance)
  local private <const> = assert(
    datatable_instance_private[instance],
    "DataTable instance not recognized: " .. tostring(self)
  )

  assert(private.datatable == self, "DataTable type method used with incompatible type")
  return private.frozen
end

local datatable_type_validate <const> = function (self, instance)
  local private <const> = assert(
    datatable_instance_private[instance],
    "DataTable instance not recognized: " .. tostring(instance)
  )

  assert(private.datatable == self, "DataTable type method used with incompatible type")
  local datatable <const> = assert(
    datatable_type_private[private.datatable],
    "DataTable type not recognized: " .. tostring(private.datatable)
  )

  local message = datatable.validator(private.data)
  if message ~= nil then
    assert(type(message) == 'string', "DataTable validator function must return a string message")
    return false, message
  end

  return true, nil
end

local datatable_type_class_methods <const> = {
  ['is']=datatable_type_is,
  ['freeze']=datatable_type_freeze,
  ['is_frozen']=datatable_type_is_frozen,
  ['validate']=datatable_type_validate,
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

local function DataTableSlot(datatable_type)
  assert(DataTable.is(datatable_type), "datatable_type must be a DataTable type instance")

  return Slot.create(function (value)
    if datatable_type:is(value) then
      return value
    end

    return nil, "value must be an instance of datatable: " .. tostring(datatable_type)
  end, function (value)
    return tostring(datatable_type)
  end)
end

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
  TableSlot=TableSlot,

  -- slot factories
  create_array_table_slot=create_array_table_slot,
  create_map_table_slot=create_map_table_slot,

  -- slot wrappers
  Optional=Optional,
  DataTableSlot=DataTableSlot,

  -- datatable
  DataTable=DataTable
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
end

return module
