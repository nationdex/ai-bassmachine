-- MCP Bass Machine - API key store
-- Keys entered in the TUI live here, outside the project checkout (so a git add can never pick them
-- up) in a user-only file. Environment variables still take precedence over this store.

local json = require("mcp-bassmachine.utils.json")
local term = require("mcp-bassmachine.utils.term")

local Secrets = {}

-- MCP_BASSMACHINE_SECRETS overrides the location (used by tests and for custom setups)
function Secrets.path()
  local override = os.getenv("MCP_BASSMACHINE_SECRETS")
  if override and #override > 0 then
    return override
  end
  return term.get_home_dir() .. "/.config/mcp-bassmachine/secrets.json"
end

function Secrets.load()
  local f = io.open(Secrets.path(), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local decoded = json.decode(content)
  if type(decoded) == "table" then
    return decoded
  end
  return {}
end

function Secrets.get(provider)
  local key = Secrets.load()[provider]
  if type(key) == "string" and #key > 0 then
    return key
  end
  return nil
end

function Secrets.validate_key(key)
  if type(key) ~= "string" then
    return false, "Key must be text"
  end
  if #key < 8 or #key > 512 then
    return false, "Key length looks wrong (expected 8-512 characters)"
  end
  if key:find("[%s%c\"'\\]") then
    return false, "Key contains spaces, quotes or control characters (bad paste?)"
  end
  return true
end

local function write_all(data)
  local path = Secrets.path()
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir then
    term.mkdir_p(dir)
  end
  local f = term.open_private(path)
  if not f then
    return false, "Could not write " .. path
  end
  f:write(json.encode(data))
  f:close()
  term.chmod_private(path)
  return true
end

function Secrets.set(provider, key)
  local ok, err = Secrets.validate_key(key)
  if not ok then
    return false, err
  end
  local data = Secrets.load()
  data[provider] = key
  return write_all(data)
end

function Secrets.delete(provider)
  local data = Secrets.load()
  if data[provider] == nil then
    return true
  end
  data[provider] = nil
  return write_all(data)
end

-- "sk-a…wxyz": enough to recognise a key, never enough to use it
function Secrets.mask(key)
  if type(key) ~= "string" or #key == 0 then
    return "(not set)"
  end
  if #key < 12 then
    return string.rep("*", #key)
  end
  return key:sub(1, 3) .. "..." .. key:sub(-4)
end

return Secrets
