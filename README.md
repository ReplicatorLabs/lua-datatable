# lua-datatable

Lua typed data tables.

* Single-file implementation with no third-party dependencies.

## Usage

Load the `datatable.lua` file as a module:

```lua
local dt <const> = require('datatable')
```

Create a DataTable type:

```lua
local Employee <const> = dt.DataTable({
  active=dt.BooleanSlot,
  full_name=dt.Slot(function (value)
    if type(value) ~= 'string' or string.len(value) == 0 then
      return nil, "value must be a non-empty string"
    end

    return value
  end, function (value)
    -- always quote full names
    return '"' .. value .. '"'
  end),
  vacation_days=dt.Slot(function (value)
    if math.type(value) ~= 'integer' or value <= 0 then
      return nil, "value must be a positive integer"
    end

    return value
  end)
}, {  -- flags are all optional
  freeze_instances=false,
  validator=(function (data)
    if data.active and data.vacation_days <= 5 then
      -- returning a non-nil value will cause an error when creating an
      -- instance or mutating an existing instance
      return "All active employees must receive at least 5 vacation days."
    end
  end)
})

assert(dt.DataTable.is(Employee))
assert(not Employee.freeze_instances)
for name, slot in pairs(Employee.slots) do
  print("Slot: " .. name)
end
```

When creating a DataTable type you can use the following built-in slots:

* `AnySlot`: does not do any type checking
* `BooleanSlot`: must be a boolean (via `type()`)
* `StringSlot`: must be a string (via `type()`)
* `NumberSlot`: must be a number (via `type()`)
* `IntegerSlot`: must be an integer (via `math.type()`)
* `FloatSlot`: must be a float (via `math.type()`)
* `TableSlot`: must be a table (via `type()`)

If you need to validate complex array or map tables you can use the following
factory functions:

* `create_array_table_slot{...}`: create a Slot to validate an array table with given constraints
* `create_map_table_slot{...}`: create a Slot to validate a map table with given constraints

The following convenience wrappers are provided:

* `Optional(internal_slot)`: validates values using the internal slot but also allows `nil`
* `DataTableSlot(datatable_type)`: values must be an instance of the given DataTable type

You can also create custom slots with validator and, optionally, formatter
functions as seen in the example above.

Create an instance of the defined DataTable type:

```lua
local employee_john_doe <const> = Employee{
  active=true,
  full_name='John Doe',
  vacation_days=(5 * 4)
}

assert(Employee:is(employee_john_doe))
assert(not Employee:is_frozen(employee_john_doe))

-- read and write slot values
employee_john_doe.active = false
employee_john_doe.vacation_days = employee_john_doe.vacation_days - 5

print("Full Name: " .. employee_john_doe.full_name)
print("Vacation Days: " .. tostring(employee_john_doe.vacation_days))

-- freeze the datatable instance to prevent modifications
Employee:freeze(employee_john_doe)
assert(Employee:is_frozen(employee_john_doe))

-- enumerate slot (key, value) pairs
for key, value in pairs(employee_john_doe) do
  print("Employee['" .. key .. "'] -> " .. tostring(value)) -- Ex: Employee['active'] -> false
end
```

See the unit tests for more exhaustive examples.

## Tests

Make sure you have the submodules available and run the `project.lua` file as
a script to run the tests:

```
git submodule update --init --recursive
env LUA_DATATABLE_LEAK_INTERNALS=TRUE lua ./project.lua
```

## Roadmap

Planned:

* [x] Lua 5.4 support.
  * [x] Unit tests.
  * [ ] Integration tests.
* [ ] DataTable custom string representations for types and instances.
  * [ ] DataTable formatter flag with matching interface to Slot formatter.
  * [ ] Slot tostring implementation.
  * [ ] DataTable instance tostring implementation.
* [ ] LuaRocks package.

Open to consideration:

* [ ] LuaJIT support.
  * [ ] Integration tests.
* [ ] Lua 5.3 support.
  * [ ] Integration tests.
* [ ] Lua 5.2 support.
  * [ ] Integration tests.
* [ ] Lua 5.1 support.
  * [ ] Integration tests.
* [ ] Support for DataTable instance value equality testing.

## References

* [LuaUnit](https://luaunit.readthedocs.io/en/latest/)
