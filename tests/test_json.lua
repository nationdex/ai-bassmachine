package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local json = require("ai-bassmachine.utils.json")

local function assert_eq(a, b, msg)
  if a ~= b then
    error(string.format("Assertion failed: %s (%s ~= %s)", msg or "", tostring(a), tostring(b)))
  end
end

-- Test primitives
assert_eq(json.encode("hello world"), '"hello world"', "encode string")
assert_eq(json.encode(42), "42", "encode integer")
assert_eq(json.encode(true), "true", "encode boolean true")
assert_eq(json.encode(false), "false", "encode boolean false")
assert_eq(json.encode(nil), "null", "encode nil")

-- Test decode primitives
assert_eq(json.decode('"test 123"'), "test 123", "decode string")
assert_eq(json.decode("999"), 999, "decode number")
assert_eq(json.decode("true"), true, "decode true")
assert_eq(json.decode("false"), false, "decode false")

-- Test array
local arr = { "a", "b", "c" }
local enc_arr = json.encode(arr)
local dec_arr = json.decode(enc_arr)
assert_eq(#dec_arr, 3, "array length")
assert_eq(dec_arr[1], "a", "array item 1")
assert_eq(dec_arr[3], "c", "array item 3")

-- Test object
local obj = { name = "mcp-bass", active = true, count = 10 }
local enc_obj = json.encode(obj)
local dec_obj = json.decode(enc_obj)
assert_eq(dec_obj.name, "mcp-bass", "object field name")
assert_eq(dec_obj.active, true, "object field active")
assert_eq(dec_obj.count, 10, "object field count")

io.write("PASS: tests/test_json.lua\n")
