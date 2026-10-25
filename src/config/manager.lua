-- MCP Bass Machine - Hybrid Configuration Manager
-- Loads, merges environment variables, provides runtime edits, and saves back to TOML.

local toml = require("mcp-bassmachine.config.toml")
local term = require("mcp-bassmachine.utils.term")

local ConfigManager = {}
ConfigManager.__index = ConfigManager

local DEFAULT_CONFIG = {
  general = {
    app_name = "MCP Bass Machine",
    log_level = "info",
    history_file = ".bassmachine_history.json",
    auto_clean_history = true,
    max_history_entries = 50,
    history_retention_hours = 24,
  },
  ui = {
    theme = "neon-bass",
    frame_rate = 30,
    show_fps = false,
    mouse_support = true,
    bass_meter = true,
  },
  ai = {
    default_provider = "zenmux",
    default_model = "deepseek/deepseek-v4.1-flash",
    temperature = 0.7,
    max_tokens = 4096,
    request_timeout_seconds = 60,
  },
  providers = {
    zenmux = {
      name = "ZenMux AI",
      base_url = "https://zenmux.ai/api/v1",
      api_key = "",
    },
    anthropic = {
      name = "Anthropic Claude",
      base_url = "https://api.anthropic.com/v1",
      api_key = "",
    },
    gemini = {
      name = "Google Gemini",
      base_url = "https://generativelanguage.googleapis.com/v1beta",
      api_key = "",
    },
    openai = {
      name = "OpenAI",
      base_url = "https://api.openai.com/v1",
      api_key = "",
    },
    openrouter = {
      name = "OpenRouter",
      base_url = "https://openrouter.ai/api/v1",
      api_key = "",
    },
    deepseek = {
      name = "DeepSeek Native",
      base_url = "https://api.deepseek.com/v1",
      api_key = "",
    },
    ollama = {
      name = "Ollama Local",
      base_url = "http://localhost:11434/v1",
      api_key = "ollama",
    },
  },
  marketplaces = {
    cache_ttl_minutes = 60,
    enable_smithery = true,
    enable_glama = true,
    enable_awesome_mcp = true,
    enable_mcp_registry = true,
  },
}

local function deep_copy(orig)
  if type(orig) ~= "table" then
    return orig
  end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local function deep_merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then
      deep_merge(dst[k], v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function expand_env_vars(tbl)
  for k, v in pairs(tbl) do
    if type(v) == "string" then
      local env_var = v:match("^%${([A-Za-z0-9_]+)}$")
      if env_var then
        local env_val = os.getenv(env_var)
        if env_val and #env_val > 0 then
          tbl[k] = env_val
        end
      end
    elseif type(v) == "table" then
      expand_env_vars(v)
    end
  end
end

-- Provider id -> environment variable holding its API key
local PROVIDER_ENV_KEYS = {
  zenmux = "ZENMUX_API_KEY",
  anthropic = "ANTHROPIC_API_KEY",
  gemini = "GEMINI_API_KEY",
  openai = "OPENAI_API_KEY",
  openrouter = "OPENROUTER_API_KEY",
  deepseek = "DEEPSEEK_API_KEY",
}

-- Values that are safe to persist in bassmachine.toml (empty, ${VAR} placeholder, ollama's dummy key)
local function is_safe_key_value(v)
  return type(v) ~= "string" or v == "" or v == "ollama" or v:match("^%${[A-Za-z0-9_]+}$") ~= nil
end

function ConfigManager.new(config_path)
  local self = setmetatable({}, ConfigManager)
  self.config_path = config_path or "bassmachine.toml"
  -- raw = what gets written to disk (env placeholders intact); data = runtime view with secrets resolved
  self.raw = deep_copy(DEFAULT_CONFIG)
  self.data = deep_copy(DEFAULT_CONFIG)
  self:load()
  return self
end

function ConfigManager:load()
  self.raw = deep_copy(DEFAULT_CONFIG)
  local f = io.open(self.config_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local parsed = toml.parse(content)
    if parsed and type(parsed) == "table" then
      deep_merge(self.raw, parsed)
    end
  end

  self.data = deep_copy(self.raw)
  expand_env_vars(self.data)

  -- Environment variables always win at runtime, but never touch self.raw
  for provider_id, env_name in pairs(PROVIDER_ENV_KEYS) do
    local env_val = os.getenv(env_name)
    if env_val and #env_val > 0 and self.data.providers[provider_id] then
      self.data.providers[provider_id].api_key = env_val
    end
  end
end

-- Persist configuration. API keys are never written as literals: anything that is not a
-- ${ENV_VAR} placeholder is replaced with the provider's placeholder before encoding.
function ConfigManager:save()
  local scrubbed = {}
  for provider_id, prov in pairs(self.raw.providers or {}) do
    if type(prov) == "table" and not is_safe_key_value(prov.api_key) then
      local env_name = PROVIDER_ENV_KEYS[provider_id] or (provider_id:upper():gsub("[^A-Z0-9]", "_") .. "_API_KEY")
      prov.api_key = "${" .. env_name .. "}"
      table.insert(scrubbed, provider_id)
    end
  end

  local raw_toml = toml.encode(self.raw)
  local f = io.open(self.config_path, "w")
  if not f then
    return false, "Could not open " .. self.config_path .. " for writing"
  end
  f:write(raw_toml)
  f:close()
  term.chmod_private(self.config_path)

  if #scrubbed > 0 then
    table.sort(scrubbed)
    return true, "Literal API key replaced by env placeholder for: " .. table.concat(scrubbed, ", ")
  end
  return true
end

function ConfigManager:get(path_str, default_val)
  local cur = self.data
  for part in path_str:gmatch("[^%.]+") do
    if type(cur) ~= "table" then
      return default_val
    end
    cur = cur[part]
  end
  if cur == nil then
    return default_val
  end
  return cur
end

local function set_path(root, parts, value)
  local cur = root
  for i = 1, #parts - 1 do
    local p = parts[i]
    if not cur[p] or type(cur[p]) ~= "table" then
      cur[p] = {}
    end
    cur = cur[p]
  end
  cur[parts[#parts]] = value
end

function ConfigManager:set(path_str, value)
  local parts = {}
  for part in path_str:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  if #parts == 0 then
    return
  end

  set_path(self.data, parts, value)
  set_path(self.raw, parts, value)
end

return ConfigManager
