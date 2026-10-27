package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local EnvManager = require("ai-bassmachine.env.manager")
local widgets = require("ai-bassmachine.ui.widgets")
local Engine = require("ai-bassmachine.ui.engine")

local tmp_anti = "/tmp/test_tui_config_anti.json"
local tmp_open = "/tmp/test_tui_config_open.json"
local tmp_claude = "/tmp/test_tui_config_claude.json"

os.remove(tmp_anti)
os.remove(tmp_open)
os.remove(tmp_claude)

local env_mgr = EnvManager.new()
env_mgr.targets = {
  { id = "antigravity_tui", name = "Antigravity", path = tmp_anti, format = "standard_mcp" },
  { id = "opencode_tui", name = "OpenCode", path = tmp_open, format = "opencode" },
  { id = "claude_tui", name = "Claude", path = tmp_claude, format = "claude_global" },
}

-- 1. Test configure_mcp with arbitrary API keys and custom env vars
local res_single = env_mgr:configure_mcp("github", {
  command = "npx",
  args = { "-y", "@modelcontextprotocol/server-github" },
  env = {
    GITHUB_PERSONAL_ACCESS_TOKEN = "ghp_real_secret_token",
  },
}, "opencode_tui")

assert(#res_single == 1, "expected 1 result for opencode_tui configure")
assert(res_single[1].success == true, "configure failed: " .. tostring(res_single[1].error))

local open_spec = env_mgr:get_target_mcp_spec("opencode_tui", "github")
assert(open_spec ~= nil, "missing github spec in opencode_tui")
assert(open_spec.env.GITHUB_PERSONAL_ACCESS_TOKEN == "ghp_real_secret_token", "token mismatch in opencode_tui")

-- 2. Test configure_mcp broadcast across all agents
local res_all = env_mgr:configure_mcp("brave-search", {
  command = "npx",
  args = { "-y", "@modelcontextprotocol/server-brave-search" },
  env = {
    BRAVE_API_KEY = "bsk_all_agents_key",
  },
}, "all")

assert(#res_all == 3, "expected 3 results for all broadcast")
for _, target in ipairs(env_mgr.targets) do
  local spec = env_mgr:get_target_mcp_spec(target.id, "brave-search")
  assert(spec ~= nil, "missing brave-search in " .. target.name)
  assert(spec.env.BRAVE_API_KEY == "bsk_all_agents_key", "brave key mismatch in " .. target.name)
end

-- 3. Test modal widget rendering
local engine = Engine.new(30)
engine:resize(24, 80)
engine:clear()

local modal_items = {
  { type = "target_agent", label = "Target Agent", value = "All Configured Agents (Broadcast)" },
  { type = "command", label = "Command", value = "npx" },
  { type = "args", label = "Arguments", value = "-y @modelcontextprotocol/server-github" },
  { type = "env_var", label = "Env: GITHUB_TOKEN", value = "ghp_test", masked = true },
}

widgets.draw_modal_config_mcp(engine, "Configure MCP: github", "github", "All Configured Agents (Broadcast)", modal_items, 1)
assert(engine.buffer[5] ~= nil, "expected modal rendered in buffer")

-- Cleanup
os.remove(tmp_anti)
os.remove(tmp_open)
os.remove(tmp_claude)

io.write("PASS: tests/test_tui_mcp_config.lua\n")
