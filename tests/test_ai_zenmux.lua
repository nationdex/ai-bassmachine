package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local ConfigManager = require("mcp-bassmachine.config.manager")
local AiProvider = require("mcp-bassmachine.ai.provider")

local config = ConfigManager.new("bassmachine.toml")
local ai = AiProvider.new(config)

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

io.write("PASS: tests/test_ai_zenmux.lua (Model: " .. resp.model .. ")\n")
