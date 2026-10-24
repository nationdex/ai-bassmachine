package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local McpClient = require("mcp-bassmachine.mcp.client")
local json = require("mcp-bassmachine.utils.json")

-- Mock pipes for testing MCP JSON-RPC protocol
local MockPipe = {}
MockPipe.__index = MockPipe

function MockPipe.new()
  return setmetatable({ buffer = {}, read_idx = 1 }, MockPipe)
end

function MockPipe:write(str)
  table.insert(self.buffer, str)
end

function MockPipe.flush() end

function MockPipe:read(fmt)
  if fmt == "*l" then
    if self.read_idx > #self.buffer then
      return nil
    end
    local line = self.buffer[self.read_idx]
    self.read_idx = self.read_idx + 1
    return line:gsub("\n$", "")
  end
  return nil
end

local in_pipe = MockPipe.new()
local out_pipe = MockPipe.new()

-- Pre-populate mock responses from server to client
-- 1. Initialize response
out_pipe:write(json.encode({
  jsonrpc = "2.0",
  id = 1,
  result = {
    protocolVersion = "2024-11-05",
    serverInfo = { name = "mock-mcp-server", version = "1.0.0" },
    capabilities = { tools = {} },
  },
}) .. "\n")

-- 2. Tools list response
out_pipe:write(json.encode({
  jsonrpc = "2.0",
  id = 2,
  result = {
    tools = {
      {
        name = "query_database",
        description = "Execute SQL query",
        inputSchema = { type = "object" },
      },
      {
        name = "read_file",
        description = "Read local file",
        inputSchema = { type = "object" },
      },
    },
  },
}) .. "\n")

local client = McpClient.new(in_pipe, out_pipe)

-- Handshake
local ok, _ = client:initialize()
assert(ok == true, "handshake failed")
assert(client.server_info.name == "mock-mcp-server", "server name mismatch")

-- List tools
local tools, terr = client:list_tools()
assert(tools ~= nil, "list_tools failed: " .. tostring(terr))
assert(#tools == 2, "expected 2 tools, got " .. #tools)
assert(tools[1].name == "query_database", "tool 1 name mismatch")

io.write("PASS: tests/test_mcp_protocol.lua\n")
