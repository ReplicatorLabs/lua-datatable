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
  active='boolean',
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
  frozen=false,
  validator=function (data)
    if data.active and data.vacation_days <= 5 then
      -- returning a non-nil value will cause an error when creating an instance
      return "All active employees must receive at least 5 vacation days."
    end
  end
})

assert(dt.DataTable.is(Employee))
assert(not Employee.frozen)
for name, slot in pairs(Employee.slots) do
  print("Slot: " .. name)
end
```

When creating a DataTable type you can use the following built-in slots:

* `any`: does not do any type checking
* `boolean`: must be a boolean (via `type()`)
* `string`: must be a string (via `type()`)
* `number`: must be a number (via `type()`)
* `integer`: must be an integer (via `math.type()`)
* `float`: must be a float (via `math.type()`)
* `table`: must be a table (via `type()`)

You can also create custom slots with validator and, optionally, formatter
functions as seen in the example above.

Create an instance of the defined DataTable type:

```lua
local employee_john_doe <const> = Employee{
  active=true,
  full_name='John Doe',
  vacation_days=(5 * 4)
}

assert(Employee.is(employee_john_doe))
assert(not employee_john_doe.frozen)

-- read and write slot values
employee_john_doe.active = false
print("Full Name: " .. employee_john_doe.full_name)
print("Vacation Days: " .. tostring(employee_john_doe.vacation_days))

-- enumerate slot (key, value) pairs
for key, value in pairs(employee_john_doe) do
  print("Employee['" .. key .. "'] -> " .. tostring(value)) -- Ex: Employee['active'] -> False
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
