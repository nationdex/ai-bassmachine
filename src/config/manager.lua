-- MCP Bass Machine - Hybrid Configuration Manager
-- Loads, merges environment variables, provides runtime edits, and saves back to TOML.

local toml = require("ai-bassmachine.config.toml")
local term = require("ai-bassmachine.utils.term")
local Secrets = require("ai-bassmachine.config.secrets")

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
  self.notices = {}
  self.key_sources = {}
  local f = io.open(self.config_path, "r")
  local file_existed = f ~= nil
  if f then
    local content = f:read("*a")
    f:close()
    local parsed = toml.parse(content)
    if parsed and type(parsed) == "table" then
      deep_merge(self.raw, parsed)
    end
  end

  -- A literal key in the TOML is a leak (older versions wrote resolved keys back to this tracked file).
  -- Drop it instead of using it, and tell the user to rotate it and enter a fresh one in Settings.
  local scrubbed = {}
  for provider_id, prov in pairs(self.raw.providers or {}) do
    if type(prov) == "table" and not is_safe_key_value(prov.api_key) then
      prov.api_key = "${"
        .. (PROVIDER_ENV_KEYS[provider_id] or (provider_id:upper():gsub("[^A-Z0-9]", "_") .. "_API_KEY"))
        .. "}"
      table.insert(scrubbed, provider_id)
    end
  end
  if #scrubbed > 0 then
    table.sort(scrubbed)
    table.insert(
      self.notices,
      "Removed plaintext API key from bassmachine.toml ("
        .. table.concat(scrubbed, ", ")
        .. "). Rotate it and set a new one in Settings."
    )
    if file_existed then
      self:save()
    end
  end

  self.data = deep_copy(self.raw)
  expand_env_vars(self.data)
  self:apply_keys()
end

-- Resolve provider keys: environment variable > secrets file > (placeholder -> empty)
function ConfigManager:apply_keys()
  for provider_id, env_name in pairs(PROVIDER_ENV_KEYS) do
    local prov = self.data.providers[provider_id]
    local raw_prov = self.raw.providers[provider_id]
    if prov and raw_prov then
      -- Always derive from the raw (placeholder) value so a cleared key cannot linger in memory
      local base = raw_prov.api_key
      local env_val = os.getenv(env_name)
      local file_val = Secrets.get(provider_id)
      if env_val and #env_val > 0 then
        prov.api_key = env_val
        self.key_sources[provider_id] = "env"
      elseif file_val then
        prov.api_key = file_val
        self.key_sources[provider_id] = "file"
      else
        prov.api_key = (type(base) == "string" and not base:match("^%${[A-Za-z0-9_]+}$")) and base or ""
        self.key_sources[provider_id] = "none"
      end
    end
  end
end

-- Providers that take an API key (everything except local ollama)
function ConfigManager.key_providers()
  local ids = {}
  for id in pairs(PROVIDER_ENV_KEYS) do
    table.insert(ids, id)
  end
  table.sort(ids)
  return ids
end

function ConfigManager:key_source(provider_id)
  return self.key_sources[provider_id] or "none"
end

function ConfigManager:masked_api_key(provider_id)
  local prov = self.data.providers[provider_id]
  return Secrets.mask(prov and prov.api_key or "")
end

-- Store a key in the user-only secrets file. Returns ok, err_or_note.
function ConfigManager:set_api_key(provider_id, key)
  if not PROVIDER_ENV_KEYS[provider_id] then
    return false, "Provider '" .. tostring(provider_id) .. "' does not use an API key"
  end
  local ok, err = Secrets.set(provider_id, key)
  if not ok then
    return false, err
  end
  self:apply_keys()
  if self.key_sources[provider_id] == "env" then
    return true, PROVIDER_ENV_KEYS[provider_id] .. " is set and overrides the stored key; unset it to use this one"
  end
  return true
end

function ConfigManager:clear_api_key(provider_id)
  local ok, err = Secrets.delete(provider_id)
  if not ok then
    return false, err
  end
  self:apply_keys()
  return true
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
