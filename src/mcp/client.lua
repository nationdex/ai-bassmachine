-- MCP Bass Machine - Model Context Protocol Client (JSON-RPC 2.0)
-- Connects, performs handshake, lists capabilities/tools, and executes calls.

local json = require("mcp-bassmachine.utils.json")

local McpClient = {}
McpClient.__index = McpClient

function McpClient.new(stdin_pipe, stdout_pipe)
  local self = setmetatable({}, McpClient)
  self.stdin = stdin_pipe
  self.stdout = stdout_pipe
  self.request_id = 1
  self.server_info = nil
  self.capabilities = nil
  self.tools = {}
  self.initialized = false
  return self
end

function McpClient:send_raw(payload_str)
  if not self.stdin then
    return false, "No stdin pipe available"
  end
  self.stdin:write(payload_str .. "\n")
  self.stdin:flush()
  return true
end

function McpClient:read_response(_timeout_seconds)
  if not self.stdout then
    return nil, "No stdout pipe available"
  end

  local line = self.stdout:read("*l")
  if not line or #line == 0 then
    return nil, "EOF or empty response"
  end

  local decoded, err = json.decode(line)
  if err then
    return nil, "JSON decode error: " .. tostring(err) .. " (raw: " .. line .. ")"
  end
  return decoded
end

function McpClient:request(method, params, timeout)
  local id = self.request_id
  self.request_id = self.request_id + 1

  local req = {
    jsonrpc = "2.0",
    id = id,
    method = method,
    params = params or {},
  }

  local payload = json.encode(req)
  local ok, send_err = self:send_raw(payload)
  if not ok then
    return nil, send_err
  end

  local resp, read_err = self:read_response(timeout)
  if not resp then
    return nil, read_err
  end

  if resp.error then
    return nil, resp.error.message or "MCP JSON-RPC error"
  end

  return resp.result
end

function McpClient:notify(method, params)
  local req = {
    jsonrpc = "2.0",
    method = method,
    params = params or {},
  }
  return self:send_raw(json.encode(req))
end

function McpClient:initialize()
  local params = {
    protocolVersion = "2024-11-05",
    capabilities = {
      tools = { listChanged = true },
      resources = { subscribe = true, listChanged = true },
      prompts = { listChanged = true },
    },
    clientInfo = {
      name = "mcp-bassmachine",
      version = "0.1.0",
    },
  }

  local result, err = self:request("initialize", params, 15)
  if not result then
    return false, "Handshake failed: " .. tostring(err)
  end

  self.server_info = result.serverInfo or { name = "Unknown MCP Server", version = "unknown" }
  self.capabilities = result.capabilities or {}
  self.initialized = true

  -- Acknowledge initialization
  self:notify("notifications/initialized")
  return true, result
end

function McpClient:list_tools()
  local result, err = self:request("tools/list", {})
  if not result then
    return nil, err
  end
  self.tools = result.tools or {}
  return self.tools
end

function McpClient:call_tool(tool_name, arguments)
  local params = {
    name = tool_name,
    arguments = arguments or {},
  }
  local result, err = self:request("tools/call", params, 30)
  if not result then
    return nil, err
  end
  return result
end

function McpClient:list_resources()
  local result, err = self:request("resources/list", {})
  if not result then
    return nil, err
  end
  return result.resources or {}
end

function McpClient:list_prompts()
  local result, err = self:request("prompts/list", {})
  if not result then
    return nil, err
  end
  return result.prompts or {}
end

function McpClient:ping()
  local result, err = self:request("ping", {})
  if not result then
    return false, err
  end
  return true
end

return McpClient
