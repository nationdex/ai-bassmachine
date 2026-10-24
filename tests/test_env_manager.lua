package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local EnvManager = require("mcp-bassmachine.env.manager")

-- Test with isolated temporary paths
local env_mgr = EnvManager.new()

local tmp_anti = "/tmp/test_env_antigravity.json"
local tmp_open = "/tmp/test_env_opencode.json"
local tmp_claude = "/tmp/test_env_claude.json"

os.remove(tmp_anti)
os.remove(tmp_open)
os.remove(tmp_claude)

env_mgr.targets = {
  {
    id = "antigravity_test",
    name = "Antigravity Test",
    path = tmp_anti,
    format = "standard_mcp",
  },
  {
    id = "opencode_test",
    name = "OpenCode Test",
    path = tmp_open,
    format = "opencode",
  },
  {
    id = "claude_test",
    name = "Claude Test",
    path = tmp_claude,
    format = "claude_global",
  },
}

-- 1. Add MCP server to all
local spec = {
  command = "uvx",
  args = { "mcp-server-git", "--repository", "/tmp" },
  env = { GIT_TERMINAL_PROMPT = "0" },
}

local add_res = env_mgr:add_mcp("test-git", spec, "all")
assert(#add_res == 3, "expected 3 results for add_mcp")
for _, r in ipairs(add_res) do
  assert(r.success == true, "target add failed: " .. tostring(r.name) .. " error: " .. tostring(r.error))
end

-- 2. Verify files and formats
local list_res = env_mgr:list_all()
assert(#list_res == 3, "expected 3 environments in summary")
for _, target in ipairs(list_res) do
  assert(target.servers["test-git"] ~= nil, "missing test-git in " .. target.name)
end

-- 3. Remove MCP server
local rem_res = env_mgr:remove_mcp("test-git", "all")
assert(#rem_res == 3, "expected 3 results for remove_mcp")
for _, r in ipairs(rem_res) do
  assert(r.success == true, "target remove failed: " .. tostring(r.name))
  assert(r.removed == true, "target expected removed=true: " .. tostring(r.name))
end

local list_after = env_mgr:list_all()
for _, target in ipairs(list_after) do
  assert(target.servers["test-git"] == nil, "expected test-git removed from " .. target.name)
end

-- Cleanup
os.remove(tmp_anti)
os.remove(tmp_open)
os.remove(tmp_claude)

io.write("PASS: tests/test_env_manager.lua\n")
