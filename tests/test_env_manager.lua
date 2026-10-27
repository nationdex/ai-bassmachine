package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local EnvManager = require("ai-bassmachine.env.manager")

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

-- 4. Test configure_mcp for single agent (OpenCode format)
local conf_single = env_mgr:configure_mcp("github-mcp", {
  command = "npx",
  args = { "-y", "@modelcontextprotocol/server-github" },
  env = { GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_secret_test_123" },
}, "opencode_test")

assert(#conf_single == 1, "expected 1 result for configure_mcp single agent")
assert(conf_single[1].success == true, "configure single failed: " .. tostring(conf_single[1].error))

local single_spec = env_mgr:get_target_mcp_spec("opencode_test", "github-mcp")
assert(single_spec ~= nil, "expected spec found for github-mcp in opencode_test")
assert(single_spec.env ~= nil and single_spec.env.GITHUB_PERSONAL_ACCESS_TOKEN == "ghp_secret_test_123", "missing env in single spec")

-- Verify other agents do not have it
local anti_spec = env_mgr:get_target_mcp_spec("antigravity_test", "github-mcp")
assert(anti_spec == nil, "antigravity_test should not have github-mcp yet")

-- 5. Test configure_mcp for all agents (broadcast)
local conf_all = env_mgr:configure_mcp("github-mcp", {
  command = "npx",
  args = { "-y", "@modelcontextprotocol/server-github", "--verbose" },
  env = {
    GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_broadcast_token_456",
    DEBUG = "1",
  },
}, "all")

assert(#conf_all == 3, "expected 3 results for broadcast configure_mcp")
for _, r in ipairs(conf_all) do
  assert(r.success == true, "broadcast configure failed on: " .. tostring(r.name))
end

for _, target in ipairs(env_mgr.targets) do
  local spec_check = env_mgr:get_target_mcp_spec(target.id, "github-mcp")
  assert(spec_check ~= nil, "missing github-mcp in " .. target.name)
  assert(spec_check.env.GITHUB_PERSONAL_ACCESS_TOKEN == "ghp_broadcast_token_456", "token mismatch in " .. target.name)
  assert(spec_check.env.DEBUG == "1", "debug flag mismatch in " .. target.name)
end

-- 6. Test updating env vars and deleting an env var (empty or false value)
env_mgr:configure_mcp("github-mcp", {
  env = {
    DEBUG = "", -- delete
    EXTRA_FLAG = "yes",
  },
}, "opencode_test")

local updated_open_spec = env_mgr:get_target_mcp_spec("opencode_test", "github-mcp")
assert(updated_open_spec.env.DEBUG == nil, "DEBUG should have been deleted")
assert(updated_open_spec.env.EXTRA_FLAG == "yes", "EXTRA_FLAG should be present")
assert(updated_open_spec.env.GITHUB_PERSONAL_ACCESS_TOKEN == "ghp_broadcast_token_456", "token preserved")

-- Cleanup
os.remove(tmp_anti)
os.remove(tmp_open)
os.remove(tmp_claude)

io.write("PASS: tests/test_env_manager.lua\n")
