package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local HistoryManager = require("mcp-bassmachine.mcp.history")

local tmp_history_file = "/tmp/test_bass_history.json"
os.remove(tmp_history_file)

local mgr = HistoryManager.new(tmp_history_file, true, 5, 1)

-- 1. Add records
for i = 1, 10 do
  mgr:add({
    name = "session_" .. tostring(i),
    command = "npx test-pkg-" .. tostring(i),
    status = "ok",
    tools_count = i,
  })
end

-- Since max_entries is 5, it should be capped at 5
local list = mgr:list()
assert(#list == 5, "expected history capped at 5 entries, got " .. #list)
assert(list[1].name == "session_10", "expected newest first")

-- Clean all
mgr:clean_all()
assert(#mgr:list() == 0, "expected 0 entries after clean_all")

os.remove(tmp_history_file)
io.write("PASS: tests/test_history.lua\n")
