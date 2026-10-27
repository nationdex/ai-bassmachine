package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local ConfigManager = require("ai-bassmachine.config.manager")

local FAKE_KEY = "sk-FAKE-regression-key-1234567890"
local path = os.tmpname()

local function read_all(p)
  local f = assert(io.open(p, "r"))
  local c = f:read("*a")
  f:close()
  return c
end

local f = assert(io.open(path, "w"))
f:write(
  '[providers.zenmux]\nname = "ZenMux AI"\nbase_url = "https://zenmux.ai/api/v1"\napi_key = "${ZENMUX_API_KEY}"\n'
)
f:close()

-- 1. Env key is resolved at runtime but never persisted by save()
local env_cfg = ConfigManager.new(path)
local real_env = os.getenv("ZENMUX_API_KEY")
if real_env and #real_env > 0 then
  assert(env_cfg:get("providers.zenmux.api_key") == real_env, "env key must be resolved at runtime")
end
env_cfg:set("ui.show_fps", true)
assert(env_cfg:save())
local saved = read_all(path)
assert(not saved:find(FAKE_KEY, 1, true), "fake key leaked")
if real_env and #real_env > 0 then
  assert(not saved:find(real_env, 1, true), "env key leaked into saved TOML")
end
assert(saved:find("${ZENMUX_API_KEY}", 1, true), "placeholder must survive save()")

-- 2. A literal key set at runtime is scrubbed back to a placeholder on save()
local lit_cfg = ConfigManager.new(path)
lit_cfg:set("providers.openai.api_key", FAKE_KEY)
assert(lit_cfg:get("providers.openai.api_key") == FAKE_KEY, "runtime view keeps the literal")
local ok, note = lit_cfg:save()
assert(ok, "save failed")
assert(note and note:find("openai", 1, true), "expected scrub notice, got " .. tostring(note))
saved = read_all(path)
assert(not saved:find(FAKE_KEY, 1, true), "literal key persisted to disk")
assert(saved:find("${OPENAI_API_KEY}", 1, true), "literal key must become env placeholder")

-- 3. Config file is private (POSIX only)
local p = io.popen("stat -c %a '" .. path .. "' 2>/dev/null")
local mode = p and p:read("*l")
if p then
  p:close()
end
if mode and #mode > 0 then
  assert(mode == "600", "expected mode 600, got " .. mode)
end

os.remove(path)
io.write("PASS: tests/test_config_secrets.lua\n")
