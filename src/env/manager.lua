-- MCP Bass Machine - Universal AI Agent MCP Environment Manager
-- Syncs, registers, and removes MCP servers across all known AI agent environments:
-- 1. Antigravity (~/.gemini/antigravity/mcp_config.json, ~/.gemini/config/mcp_config.json)
-- 2. OpenCode (~/.config/opencode/opencode.json)
-- 3. Claude Code & Desktop (~/.claude.json)
-- 4. Cursor IDE (~/.config/Cursor/User/mcp.json)
-- 5. VS Code & Insiders (~/.config/Code/User/mcp.json, ~/.config/Code - Insiders/User/mcp.json)

local json = require("mcp-bassmachine.utils.json")
local term = require("mcp-bassmachine.utils.term")

local EnvManager = {}
EnvManager.__index = EnvManager

local get_home_dir = term.get_home_dir

local function build_target_agents()
  local home = get_home_dir()
  local appdata = os.getenv("APPDATA")
  if appdata then
    appdata = appdata:gsub("\\", "/")
  end

  local cursor_path = appdata and (appdata .. "/Cursor/User/mcp.json") or (home .. "/.config/Cursor/User/mcp.json")
  local vscode_path = appdata and (appdata .. "/Code/User/mcp.json") or (home .. "/.config/Code/User/mcp.json")
  local vscode_insiders_path = appdata and (appdata .. "/Code - Insiders/User/mcp.json")
    or (home .. "/.config/Code - Insiders/User/mcp.json")

  return {
    {
      id = "antigravity",
      name = "Antigravity (Global)",
      path = home .. "/.gemini/antigravity/mcp_config.json",
      format = "standard_mcp",
    },
    {
      id = "antigravity_cli",
      name = "Antigravity CLI",
      path = home .. "/.gemini/config/mcp_config.json",
      format = "standard_mcp",
    },
    {
      id = "opencode",
      name = "OpenCode",
      path = home .. "/.config/opencode/opencode.json",
      format = "opencode",
    },
    {
      id = "claude",
      name = "Claude (Code & Desktop)",
      path = home .. "/.claude.json",
      format = "claude_global",
    },
    {
      id = "cursor",
      name = "Cursor IDE",
      path = cursor_path,
      format = "standard_mcp",
    },
    {
      id = "vscode",
      name = "VS Code",
      path = vscode_path,
      format = "standard_mcp",
    },
    {
      id = "vscode_insiders",
      name = "VS Code Insiders",
      path = vscode_insiders_path,
      format = "standard_mcp",
    },
  }
end
function EnvManager.new()
  local self = setmetatable({}, EnvManager)
  self.targets = build_target_agents()
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
  local dir = filepath:match("^(.*)[/\\][^/\\]+$")
  if dir then
    term.mkdir_p(dir)
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
        if type(server_spec.command) == "table" then
          for _, c in ipairs(server_spec.command) do
            table.insert(cmd_list, c)
          end
        else
          table.insert(cmd_list, server_spec.command)
        end
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
      local cmd = server_spec.command
      local args = server_spec.args or {}
      if type(cmd) == "table" then
        local copy = {}
        for _, c in ipairs(cmd) do
          table.insert(copy, c)
        end
        cmd = table.remove(copy, 1)
        args = copy
      end
      local res = {
        command = cmd,
        args = args,
      }
      if server_spec.env then
        res.env = server_spec.env
      end
      return res
    end
  end
end

-- Normalize an agent's server representation into a standard spec
local function normalize_server_spec(spec)
  if not spec or type(spec) ~= "table" then
    return nil
  end

  local norm = {}
  if spec.url and #spec.url > 0 then
    norm.url = spec.url
    norm.headers = spec.headers
    return norm
  end

  if spec.type == "local" and spec.command and type(spec.command) == "table" then
    local copy = {}
    for _, c in ipairs(spec.command) do
      table.insert(copy, c)
    end
    norm.command = table.remove(copy, 1)
    norm.args = copy
    norm.env = spec.environment or spec.env
    return norm
  end

  norm.command = spec.command
  norm.args = spec.args or {}
  norm.env = spec.env or spec.environment
  return norm
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

-- Find existing spec of an installed MCP server across all agents
function EnvManager:find_mcp_spec(server_name)
  local summary = self:list_all()
  local target_sname = server_name:lower()

  for _, target in ipairs(summary) do
    if target.servers then
      for sname, raw_spec in pairs(target.servers) do
        if sname:lower() == target_sname or sname:lower():gsub("[^%w]", "") == target_sname:gsub("[^%w]", "") then
          return normalize_server_spec(raw_spec), sname, target
        end
      end
    end
  end
  return nil, nil, nil
end

-- Check presence of an MCP across each agent environment
function EnvManager:get_mcp_presence(server_name)
  local summary = self:list_all()
  local target_sname = server_name:lower()
  local presence = {}

  for _, target in ipairs(summary) do
    local found = false
    local spec_found = nil
    if target.servers then
      for sname, raw_spec in pairs(target.servers) do
        if sname:lower() == target_sname or sname:lower():gsub("[^%w]", "") == target_sname:gsub("[^%w]", "") then
          found = true
          spec_found = raw_spec
          break
        end
      end
    end
    table.insert(presence, {
      target_id = target.id,
      target_name = target.name,
      installed = found,
      spec = spec_found,
    })
  end

  return presence
end

-- Broadcast/install an existent MCP to ALL agent environments that lack it
function EnvManager:sync_mcp_to_all(server_name)
  local spec, canonical_name, source_agent = self:find_mcp_spec(server_name)
  if not spec then
    return false, "MCP '" .. server_name .. "' not found in any configured agent environment."
  end

  local actual_name = canonical_name or server_name
  local results = self:add_mcp(actual_name, spec, "all")
  local newly_installed = 0
  local total_ok = 0

  for _, res in ipairs(results) do
    if res.success then
      total_ok = total_ok + 1
      newly_installed = newly_installed + 1
    end
  end

  return true,
    {
      server_name = actual_name,
      spec = spec,
      source_agent = source_agent and source_agent.name or "Unknown",
      total_installed = total_ok,
      results = results,
    }
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
