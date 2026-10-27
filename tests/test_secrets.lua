-- luacheck: ignore 122
package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local Secrets = require("ai-bassmachine.config.secrets")
local ConfigManager = require("ai-bassmachine.config.manager")

local function tmp(name)
  return os.tmpname() .. name
end
local function read_all(p)
  local f = io.open(p, "r")
  if not f then
    return nil
  end
  local c = f:read("*a")
  f:close()
  return c
end

-- Isolate the store from the developer's real keys. os.getenv cannot be set from Lua, so wrap it.
local secrets_path = tmp(".secrets.json")
local real_getenv = os.getenv
os.getenv = function(name)
  if name == "MCP_BASSMACHINE_SECRETS" then
    return secrets_path
  end
  if name:match("_API_KEY$") then
    return nil -- ignore the host's real keys so source resolution is deterministic
  end
  return real_getenv(name)
end

local KEY = "sk-FAKE-store-key-abcdef123456"

-- 1. validation
assert(not Secrets.validate_key("short"), "short key accepted")
assert(not Secrets.validate_key("has space in key 12345"), "whitespace key accepted")
assert(not Secrets.validate_key('quote"in-key-123456'), "quote key accepted")
assert(Secrets.validate_key(KEY), "good key rejected")

-- 2. set/get/delete round trip, mask never reveals the middle
assert(Secrets.set("zenmux", KEY))
assert(Secrets.get("zenmux") == KEY)
assert(Secrets.mask(KEY) == "sk-...3456", "mask: " .. Secrets.mask(KEY))
assert(not Secrets.mask(KEY):find("abcdef", 1, true))
assert(Secrets.delete("zenmux"))
assert(Secrets.get("zenmux") == nil)

-- 3. file is private on POSIX
Secrets.set("zenmux", KEY)
local p = io.popen("stat -c %a '" .. secrets_path .. "' 2>/dev/null")
local mode = p and p:read("*l")
if p then
  p:close()
end
if mode and #mode > 0 then
  assert(mode == "600", "secrets file mode " .. mode)
end

-- 4. config integration: key flows to runtime, never into the TOML
local toml_path = tmp(".toml")
local cfg = ConfigManager.new(toml_path)
assert(cfg:key_source("zenmux") == "file", "expected file source, got " .. cfg:key_source("zenmux"))
assert(cfg:get("providers.zenmux.api_key") == KEY)
assert(cfg:masked_api_key("zenmux") == "sk-...3456")
assert(cfg:set_api_key("openai", "sk-FAKE-openai-key-0987654321"))
assert(cfg:key_source("openai") == "file")
assert(cfg:save())
assert(not (read_all(toml_path) or ""):find("FAKE", 1, true), "key leaked into TOML")
assert(cfg:clear_api_key("openai"))
assert(cfg:key_source("openai") == "none")
assert(cfg:get("providers.openai.api_key") == "", "placeholder must resolve to empty when unset")
local ok, err = cfg:set_api_key("ollama", KEY)
assert(not ok and err, "ollama must not accept keys")
local bad_ok = cfg:set_api_key("zenmux", "bad key")
assert(not bad_ok, "invalid key accepted")

-- 5. legacy plaintext key in TOML (written by old versions) is dropped, reported and scrubbed on disk
local legacy_path = tmp(".legacy.toml")
local lf = assert(io.open(legacy_path, "w"))
lf:write(
  '[providers.openrouter]\nname = "OpenRouter"\nbase_url = "https://openrouter.ai/api/v1"\napi_key = "sk-or-LEAKED-legacy-key-777777"\n'
)
lf:close()
Secrets.delete("openrouter")
local legacy = ConfigManager.new(legacy_path)
assert(legacy:get("providers.openrouter.api_key") ~= "sk-or-LEAKED-legacy-key-777777", "legacy key still used")
assert(legacy.notices[1] and legacy.notices[1]:find("openrouter", 1, true), "no scrub notice")
assert(not (read_all(legacy_path) or ""):find("LEAKED", 1, true), "legacy key still on disk")

os.getenv = real_getenv
os.remove(secrets_path)
os.remove(toml_path)
os.remove(legacy_path)
io.write("PASS: tests/test_secrets.lua\n")
