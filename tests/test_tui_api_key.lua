-- luacheck: ignore 122
-- Renders the Settings tab and the key modal with a fake key; the full key must never reach the screen.
package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local ConfigManager = require("ai-bassmachine.config.manager")
local views = require("ai-bassmachine.ui.views")
local Engine = require("ai-bassmachine.ui.engine")
local widgets = require("ai-bassmachine.ui.widgets")

local KEY = "sk-FAKE-screen-key-QWERTY998877"
local secrets_path = os.tmpname()
local real_getenv = os.getenv
os.getenv = function(name)
  if name == "MCP_BASSMACHINE_SECRETS" then
    return secrets_path
  end
  if name:match("_API_KEY$") then
    return nil
  end
  return real_getenv(name)
end

local config = ConfigManager.new("/nonexistent/bassmachine.toml")
assert(config:set_api_key("zenmux", KEY))

local function screen_text(engine)
  local rows = {}
  for r = 1, engine.rows do
    local line = {}
    for c = 1, engine.cols do
      local cell = engine.buffer[r][c]
      line[#line + 1] = (cell and cell.char ~= "" and cell.char) or " "
    end
    rows[#rows + 1] = table.concat(line)
  end
  return table.concat(rows, "\n")
end

local engine = Engine.new(30)
local state = { selected_setting_idx = 9 }
views.render_settings(engine, config, state)
local text = screen_text(engine)
assert(text:find("API Key", 1, true), "API key row missing from Settings")
assert(text:find("sk-...8877", 1, true), "masked key not shown")
assert(text:find("secrets file", 1, true), "key source not shown")
assert(not text:find("QWERTY", 1, true), "full key rendered in Settings")

-- Masked modal: typed characters become asterisks
local engine2 = Engine.new(30)
widgets.draw_modal_input(engine2, "API Key: ZENMUX", "Paste key", KEY, #KEY, true)
local modal_text = screen_text(engine2)
assert(not modal_text:find("QWERTY", 1, true) and not modal_text:find("sk-FAKE", 1, true), "key visible in modal")
assert(modal_text:find("****", 1, true), "mask asterisks missing")

os.getenv = real_getenv
os.remove(secrets_path)
io.write("PASS: tests/test_tui_api_key.lua\n")
