package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local ConfigManager = require("mcp-bassmachine.config.manager")
local AiProvider = require("mcp-bassmachine.ai.provider")

local config = ConfigManager.new("bassmachine.toml")
local ai = AiProvider.new(config)

local zm_key = os.getenv("ZENMUX_API_KEY")

-- If ZENMUX_API_KEY is configured in the environment, verify live network inference;
-- otherwise verify dynamic model indexer and schema contract.
if zm_key and #zm_key > 0 then
  local resp, err = ai:chat_completion({
    { role = "user", content = "Reply with exactly: BASS_CONFIRMED" },
  }, {
    provider = "zenmux",
    model = "deepseek/deepseek-v4.1-flash",
  })

  if not resp then
    error("ZenMux test failed: " .. tostring(err))
  end

  assert(resp.content:find("BASS_CONFIRMED") ~= nil, "Response did not contain BASS_CONFIRMED: " .. resp.content)
  assert(resp.model:find("deepseek") ~= nil, "Expected deepseek model, got: " .. tostring(resp.model))

  io.write("PASS: tests/test_ai_zenmux.lua (Live API Model: " .. resp.model .. ")\n")
else
  local models = ai:fetch_available_models("zenmux")
  assert(#models > 0, "Expected available models for zenmux")
  local openrouter_models = ai:fetch_available_models("openrouter")
  assert(#openrouter_models > 0, "Expected available models for openrouter")
  local anthropic_models = ai:fetch_available_models("anthropic")
  assert(#anthropic_models > 0, "Expected available models for anthropic")

  io.write("PASS: tests/test_ai_zenmux.lua (Dynamic models indexed across providers)\n")
end
