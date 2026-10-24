-- MCP Bass Machine - Hybrid Configuration Manager
-- Loads, merges environment variables, provides runtime edits, and saves back to TOML.

local toml = require("mcp-bassmachine.config.toml")

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
      default_model = "deepseek/deepseek-v4.1-flash",
    },
    openrouter = {
      name = "OpenRouter",
      base_url = "https://openrouter.ai/api/v1",
      api_key = "",
      default_model = "anthropic/claude-3.5-sonnet",
    },
    deepseek = {
      name = "DeepSeek Native",
      base_url = "https://api.deepseek.com/v1",
      api_key = "",
      default_model = "deepseek-chat",
    },
    ollama = {
      name = "Ollama Local",
      base_url = "http://localhost:11434/v1",
      api_key = "ollama",
      default_model = "llama3:latest",
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

function ConfigManager.new(config_path)
  local self = setmetatable({}, ConfigManager)
  self.config_path = config_path or "bassmachine.toml"
  self.data = deep_copy(DEFAULT_CONFIG)
  self:load()
  return self
end

function ConfigManager:load()
  local f = io.open(self.config_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local parsed = toml.parse(content)
    if parsed and type(parsed) == "table" then
      deep_merge(self.data, parsed)
    end
  end
  expand_env_vars(self.data)

  -- Check direct environment variable overrides
  local zm_key = os.getenv("ZENMUX_API_KEY")
  if zm_key and #zm_key > 0 then
    self.data.providers.zenmux.api_key = zm_key
  end
  local or_key = os.getenv("OPENROUTER_API_KEY")
  if or_key and #or_key > 0 then
    self.data.providers.openrouter.api_key = or_key
  end
  local ds_key = os.getenv("DEEPSEEK_API_KEY")
  if ds_key and #ds_key > 0 then
    self.data.providers.deepseek.api_key = ds_key
  end
end

function ConfigManager:save()
  local raw_toml = toml.encode(self.data)
  local f = io.open(self.config_path, "w")
  if not f then
    return false, "Could not open " .. self.config_path .. " for writing"
  end
  f:write(raw_toml)
  f:close()
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

function ConfigManager:set(path_str, value)
  local parts = {}
  for part in path_str:gmatch("[^%.]+") do
    table.insert(parts, part)
  end
  if #parts == 0 then
    return
  end

  local cur = self.data
  for i = 1, #parts - 1 do
    local p = parts[i]
    if not cur[p] or type(cur[p]) ~= "table" then
      cur[p] = {}
    end
    cur = cur[p]
  end
  cur[parts[#parts]] = value
end

return ConfigManager
