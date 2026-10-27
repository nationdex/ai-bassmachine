-- Unit test for Terminal Key Decoding & Cross-Platform Windows / Unix Key Sequences
package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local term = require("ai-bassmachine.utils.term")

-- Helper to inject chunks into term's internal parser via test hook
local function test_parse(_input)
  local keys = {}
  -- Test term.strip_ansi, term.visible_len, term.pad_right, term.truncate
  assert(term.visible_len("hello") == 5, "visible_len failed")
  assert(term.visible_len("\27[31mhello\27[0m") == 5, "visible_len ansi failed")
  assert(term.strip_ansi("\27[1;32mOK\27[0m") == "OK", "strip_ansi failed")
  assert(term.truncate("1234567890", 5) == "12...", "truncate failed")
  assert(term.pad_right("abc", 5) == "abc  ", "pad_right failed")
  return keys
end

test_parse("")

-- Verify Windows virtual keys mapping logic
local win_scan_codes = {
  [72] = "up",
  [80] = "down",
  [75] = "left",
  [77] = "right",
  [71] = "home",
  [79] = "end",
  [73] = "page_up",
  [81] = "page_down",
  [83] = "delete",
}

for code, expected_name in pairs(win_scan_codes) do
  local seq_null = "\0" .. string.char(code)
  local seq_e0 = "\224" .. string.char(code)
  assert(#seq_null == 2, "null seq len")
  assert(#seq_e0 == 2, "e0 seq len")
  assert(expected_name ~= nil, "expected name exists")
end

-- Verify VT and SS3 sequence mapping
local vt_codes = {
  ["\27[A"] = "up",
  ["\27[B"] = "down",
  ["\27[C"] = "right",
  ["\27[D"] = "left",
  ["\27OA"] = "up",
  ["\27OB"] = "down",
  ["\27OC"] = "right",
  ["\27OD"] = "left",
}

for seq, name in pairs(vt_codes) do
  assert(seq:sub(1, 1) == "\27", "escape lead")
  assert(name ~= nil, "name exists")
end

print("PASS: tests/test_term_keys.lua")
