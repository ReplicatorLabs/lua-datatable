#!/usr/bin/env lua

-- enable warnings so we can see any relevant messages while running
-- tests or benchmarks through this script
warn("@on")

-- luaunit captures the value of the interpreter arguments on import which
-- makes it hard to implement a custom command line interface so store the
-- argument in a separate local table before importing it
local LUA_INTERPRETER_ARGS <const> = assert(arg, "interpreter arguments are missing")
arg = nil

--[[
Imports
--]]

local lu <const> = require('luaunit/luaunit')
local tests <const> = require('datatable_tests')

--[[
Command Line Interface
--]]

-- run unit and integration tests
local function cli_test(...)
  if os.getenv('LUA_DATATABLE_LEAK_INTERNALS') ~= 'TRUE' then
    error("LUA_DATATABLE_LEAK_INTERNALS environment variable must be 'TRUE' in order to run tests")
    os.exit(1)
  end

  os.exit(lu.LuaUnit.run(...))
end

-- minimal command line interface
local CLI_USAGE_HELP <const> = [[
<command> [args]

commands:
  test [LuaUnit args]     run unit and integration tests
]]

if #LUA_INTERPRETER_ARGS == 0 then
  print(LUA_INTERPRETER_ARGS[0] .. " " .. CLI_USAGE_HELP)
  os.exit(0)
end

local COMMANDS <const> = {
  ['test']=cli_test,
}

local command <const> = LUA_INTERPRETER_ARGS[1]
local command_handler <const> = COMMANDS[command]
if not command_handler then
  print("invalid command: " .. command)
  os.exit(1)
end

local command_arguments <const> = {}
for index, argument in ipairs(LUA_INTERPRETER_ARGS) do
  if index > 1 then
    table.insert(command_arguments, argument)
  end
end

command_handler(table.unpack(command_arguments))
