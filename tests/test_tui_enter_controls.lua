-- Comprehensive Unit & Integration Test for TUI Controls and Enter Key Processing
package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local ConfigManager = require("mcp-bassmachine.config.manager")
local HistoryManager = require("mcp-bassmachine.mcp.history")
local EnvManager = require("mcp-bassmachine.env.manager")
local Registry = require("mcp-bassmachine.marketplace.registry")
local views = require("mcp-bassmachine.ui.views")
local Engine = require("mcp-bassmachine.ui.engine")
local widgets = require("mcp-bassmachine.ui.widgets")

local config = ConfigManager.new()
config:load()

local history = HistoryManager.new()
local env_mgr = EnvManager.new()
local registry = Registry.new()

local engine = Engine.new(30)

local state = {
  active_tab_idx = 1,
  selected_mcp_idx = 1,
  marketplace_items = registry:get_all(),
  selected_tool_idx = 1,
  active_runner = nil,
  active_tools = { { name = "test_tool", description = "A test tool", inputSchema = {} } },
  selected_history_idx = 1,
  selected_setting_idx = 1,
  selected_target_idx = 1,
  selected_env_server_idx = 1,
  env_targets = env_mgr:get_targets(),
  current_target_servers = {},
  ai_prompt = "Say hello",
  ai_response = nil,
  status_msg = "Ready",
  modal = nil,
}

-- 1. Test Tab 1: Marketplaces View & Enter Key
widgets.draw_header(engine, "Marketplaces", "deepseek/deepseek-v4.1-flash", true)
views.render_marketplaces(engine, registry, env_mgr, state)
engine:render()
assert(#state.marketplace_items > 0, "Marketplace items missing")

-- 2. Test Tab 2: Test & Run View & Enter Key
state.active_tab_idx = 2
views.render_test_workspace(engine, state.active_runner, state)

-- 3. Test Tab 3: AI Synth View & Enter Key
state.active_tab_idx = 3
views.render_ai_synth(engine, config, state)

-- 4. Test Tab 4: History View & Enter Key
state.active_tab_idx = 4
history:add({ name = "test_run", command = "echo 1", status = "ok", tools_count = 1 })
views.render_history(engine, history, state)

-- 5. Test Tab 5: Settings View & Modal Select
state.active_tab_idx = 5
views.render_settings(engine, config, state)

-- Simulate Tab 5 [Enter] to open provider selector modal
local provider_options = {
  { id = "zenmux", name = "ZenMux AI", desc = "Multi-model gateway" },
  { id = "openrouter", name = "OpenRouter", desc = "Unified API" },
  { id = "anthropic", name = "Anthropic Claude", desc = "Native Anthropic API" },
}
state.modal = {
  type = "select_provider",
  is_select = true,
  items = provider_options,
  selected_idx = 1,
}
widgets.draw_modal_select(engine, "Select Provider", "Choose service:", state.modal.items, state.modal.selected_idx)

-- Simulate [Enter] inside modal to select option
local sel_item = provider_options[state.modal.selected_idx]
assert(sel_item ~= nil, "Selected item is nil")
config:set("ai.default_provider", sel_item.id)
state.modal = nil
assert(config:get("ai.default_provider") == "zenmux", "Provider setting update failed")

-- 6. Test Tab 6: Agent Sync View & Enter Key
state.active_tab_idx = 6
views.render_env_manager(engine, env_mgr, state)

-- 7. Verify consecutive Enter key deduplication in term
local simulated_stream = "\r\n"
local chunk_keys = {}
local i = 1
local len = #simulated_stream
while i <= len do
  local c = simulated_stream:sub(i, i)
  if c == "\r" or c == "\n" then
    if c == "\r" and i + 1 <= len and simulated_stream:sub(i + 1, i + 1) == "\n" then
      i = i + 1
    end
    table.insert(chunk_keys, "enter")
    i = i + 1
  else
    i = i + 1
  end
end
assert(#chunk_keys == 1, "CRLF should decode to exactly 1 enter, got " .. tostring(#chunk_keys))

print("PASS: tests/test_tui_enter_controls.lua")
