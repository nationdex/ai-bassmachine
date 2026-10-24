-- MCP Bass Machine - Universal AI Agent MCP Environment Manager
-- Syncs, registers, and removes MCP servers across all known AI agent environments:
-- 1. Antigravity (~/.gemini/antigravity/mcp_config.json, ~/.gemini/config/mcp_config.json)
-- 2. OpenCode (~/.config/opencode/opencode.json)
-- 3. Claude Code & Desktop (~/.claude.json)
-- 4. Cursor IDE (~/.config/Cursor/User/mcp.json)
-- 5. VS Code & Insiders (~/.config/Code/User/mcp.json, ~/.config/Code - Insiders/User/mcp.json)

local json = require("mcp-bassmachine.utils.json")

local EnvManager = {}
EnvManager.__index = EnvManager

local TARGET_AGENTS = {
  {
    id = "antigravity",
    name = "Antigravity (Global)",
    path = os.getenv("HOME") .. "/.gemini/antigravity/mcp_config.json",
    format = "standard_mcp",
  },
  {
    id = "antigravity_cli",
    name = "Antigravity CLI",
    path = os.getenv("HOME") .. "/.gemini/config/mcp_config.json",
    format = "standard_mcp",
  },
  {
    id = "opencode",
    name = "OpenCode",
    path = os.getenv("HOME") .. "/.config/opencode/opencode.json",
    format = "opencode",
  },
  {
    id = "claude",
    name = "Claude (Code & Desktop)",
    path = os.getenv("HOME") .. "/.claude.json",
    format = "claude_global",
  },
  {
    id = "cursor",
    name = "Cursor IDE",
    path = os.getenv("HOME") .. "/.config/Cursor/User/mcp.json",
    format = "standard_mcp",
  },
  {
    id = "vscode",
    name = "VS Code",
    path = os.getenv("HOME") .. "/.config/Code/User/mcp.json",
    format = "standard_mcp",
  },
  {
    id = "vscode_insiders",
    name = "VS Code Insiders",
    path = os.getenv("HOME") .. "/.config/Code - Insiders/User/mcp.json",
    format = "standard_mcp",
  },
}

function EnvManager.new()
  local self = setmetatable({}, EnvManager)
  self.targets = TARGET_AGENTS
  return self
end

function EnvManager:get_targets()
  return self.targets
end

local function read_json_file(filepath)
  local f = io.open(filepath, "r")
  if not f then
    return nil, "File not found: " .. filepath
  end
  local content = f:read("*a")
  f:close()
  if not content or #content == 0 then
    return {}, nil
  end
  local data, err = json.decode(content)
  if err then
    return nil, err
  end
  return data or {}, nil
end

local function write_json_file(filepath, data)
  -- Ensure parent directory exists
  local dir = filepath:match("^(.*)/[^/]+$")
  if dir then
    os.execute(string.format("mkdir -p '%s' 2>/dev/null", dir))
  end

  local f = io.open(filepath, "w")
  if not f then
    return false, "Cannot write to " .. filepath
  end
  f:write(json.encode(data))
  f:close()
  return true, nil
end

-- Convert standard MCP server spec to target agent format
local function format_server_for_target(target_format, server_spec)
  local is_remote = (server_spec.url ~= nil and #server_spec.url > 0)

  if target_format == "opencode" then
    if is_remote then
      local res = {
        type = "remote",
        url = server_spec.url,
        enabled = true,
      }
      if server_spec.headers then
        res.headers = server_spec.headers
      end
      return res
    else
      local cmd_list = {}
      if server_spec.command then
        table.insert(cmd_list, server_spec.command)
      end
      if server_spec.args then
        for _, a in ipairs(server_spec.args) do
          table.insert(cmd_list, a)
        end
      end
      local res = {
        type = "local",
        command = cmd_list,
      }
      if server_spec.env then
        res.environment = server_spec.env
      end
      return res
    end
  else
    -- Standard "mcpServers" schema (Antigravity, Claude, VSCode, Cursor)
    if is_remote then
      local res = {
        url = server_spec.url,
      }
      if server_spec.headers then
        res.headers = server_spec.headers
      end
      return res
    else
      local res = {
        command = server_spec.command,
        args = server_spec.args or {},
      }
      if server_spec.env then
        res.env = server_spec.env
      end
      return res
    end
  end
end

-- List installed MCPs across all environments
function EnvManager:list_all()
  local summary = {}

  for _, target in ipairs(self.targets) do
    local data = read_json_file(target.path)
    local target_servers = {}
    if data then
      if target.format == "opencode" then
        local mcp = data.mcp or {}
        for name, spec in pairs(mcp) do
          target_servers[name] = spec
        end
      else
        local mcp = data.mcpServers or {}
        for name, spec in pairs(mcp) do
          target_servers[name] = spec
        end
      end
    end

    table.insert(summary, {
      id = target.id,
      name = target.name,
      path = target.path,
      exists = (data ~= nil),
      servers = target_servers,
    })
  end

  return summary
end

-- Add MCP to specific or all targets
function EnvManager:add_mcp(server_name, server_spec, target_id)
  local results = {}

  for _, target in ipairs(self.targets) do
    if not target_id or target_id == "all" or target.id == target_id then
      local data, _ = read_json_file(target.path)
      if not data then
        data = {}
      end

      local formatted = format_server_for_target(target.format, server_spec)

      if target.format == "opencode" then
        if not data.mcp or type(data.mcp) ~= "table" then
          data.mcp = {}
        end
        data.mcp[server_name] = formatted
      else
        if not data.mcpServers or type(data.mcpServers) ~= "table" then
          data.mcpServers = {}
        end
        data.mcpServers[server_name] = formatted
      end

      local ok, werr = write_json_file(target.path, data)
      table.insert(results, {
        target = target.id,
        name = target.name,
        path = target.path,
        success = ok,
        error = werr,
      })
    end
  end

  return results
end

-- Remove MCP from specific or all targets
function EnvManager:remove_mcp(server_name, target_id)
  local results = {}

  for _, target in ipairs(self.targets) do
    if not target_id or target_id == "all" or target.id == target_id then
      local data, _ = read_json_file(target.path)
      local removed = false

      if data then
        if target.format == "opencode" then
          if data.mcp and data.mcp[server_name] then
            data.mcp[server_name] = nil
            removed = true
          end
        else
          if data.mcpServers and data.mcpServers[server_name] then
            data.mcpServers[server_name] = nil
            removed = true
          end
        end

        if removed then
          local ok, werr = write_json_file(target.path, data)
          table.insert(results, {
            target = target.id,
            name = target.name,
            path = target.path,
            success = ok,
            removed = true,
            error = werr,
          })
        else
          table.insert(results, {
            target = target.id,
            name = target.name,
            path = target.path,
            success = true,
            removed = false,
          })
        end
      end
    end
  end

  return results
end

return EnvManager
