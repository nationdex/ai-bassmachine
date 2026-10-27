-- Drives a real child process over stdio through McpRunner. Runs on POSIX (FIFOs) and on Windows
-- (native Win32 pipes), so the same assertions guard both code paths.
package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local term = require("ai-bassmachine.utils.term")
local McpRunner = require("ai-bassmachine.mcp.runner")

local interpreter = arg and arg[-1] or "lua"
local command = string.format('"%s" tests/fixtures/fake_mcp_server.lua', interpreter)
if not term.is_windows then
  command = string.format("'%s' tests/fixtures/fake_mcp_server.lua", interpreter)
end

local runner = McpRunner.new(command)
local ok, client = runner:start()
assert(ok, "runner failed to start: " .. tostring(client) .. " | stderr: " .. runner:get_stderr_log())
assert(client.server_info and client.server_info.name == "fake", "handshake did not reach fake server")

local tools = client:list_tools()
assert(tools and #tools == 1 and tools[1].name == "echo", "tools/list round trip failed")

runner:stop()
assert(not runner.is_running, "runner still marked running after stop")

-- Silent server must time out, not hang the UI loop (Windows reader deadline)
if term.is_windows then
  local silent = McpRunner.new(string.format('"%s" -e "io.read()"', interpreter), nil, 1500)
  local sok, serr = silent:start()
  assert(not sok and tostring(serr):find("Handshake failed"), "expected handshake failure, got " .. tostring(serr))
end

io.write(
  "PASS: tests/test_runner_stdio.lua (" .. (term.is_windows and "windows native pipes" or "posix fifos") .. ")\n"
)
