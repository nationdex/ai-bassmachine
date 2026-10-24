-- MCP Bass Machine - Ephemeral MCP Process Runner
-- Spawns MCP processes interactively via Linux FIFOs with zero permanent install.

local McpClient = require("mcp-bassmachine.mcp.client")

local McpRunner = {}
McpRunner.__index = McpRunner

local runner_counter = 0

function McpRunner.new(command_str, env_vars)
  local self = setmetatable({}, McpRunner)
  runner_counter = runner_counter + 1
  self.id = tostring(os.time()) .. "_" .. tostring(runner_counter)
  self.command = command_str
  self.env = env_vars or {}
  self.fifo_in = string.format("/tmp/mcp_bass_in_%s.fifo", self.id)
  self.fifo_out = string.format("/tmp/mcp_bass_out_%s.fifo", self.id)
  self.log_file = string.format("/tmp/mcp_bass_err_%s.log", self.id)
  self.pid_file = string.format("/tmp/mcp_bass_pid_%s.pid", self.id)
  self.pid = nil
  self.in_handle = nil
  self.out_handle = nil
  self.client = nil
  self.is_running = false
  self.start_time = 0
  return self
end

function McpRunner:start()
  -- Create FIFOs
  os.execute(string.format("mkfifo %s %s 2>/dev/null", self.fifo_in, self.fifo_out))

  -- Build environment prefix
  local env_str = ""
  for k, v in pairs(self.env) do
    env_str = env_str .. string.format('%s="%s" ', k, tostring(v))
  end

  -- Spawn background process wrapped in subshell capturing PID
  local spawn_cmd = string.format(
    "( %s%s < %s > %s 2> %s & echo $! > %s ) 2>/dev/null",
    env_str,
    self.command,
    self.fifo_in,
    self.fifo_out,
    self.log_file,
    self.pid_file
  )

  self.start_time = os.time()
  os.execute(spawn_cmd)

  -- Read PID
  local pf = io.open(self.pid_file, "r")
  if pf then
    local p = pf:read("*l")
    pf:close()
    if p then
      self.pid = tonumber(p)
    end
  end

  -- Open handles (write to fifo_in, read from fifo_out)
  self.in_handle = io.open(self.fifo_in, "w")
  self.out_handle = io.open(self.fifo_out, "r")

  if not self.in_handle or not self.out_handle then
    self:stop()
    return false, "Failed to connect to MCP process pipes"
  end

  self.client = McpClient.new(self.in_handle, self.out_handle)
  self.is_running = true

  -- Perform handshake
  local ok, err = self.client:initialize()
  if not ok then
    self:stop()
    return false, "Handshake failed: " .. tostring(err)
  end

  return true, self.client
end

function McpRunner:stop()
  if self.in_handle then
    pcall(function()
      self.in_handle:close()
    end)
    self.in_handle = nil
  end
  if self.out_handle then
    pcall(function()
      self.out_handle:close()
    end)
    self.out_handle = nil
  end

  if self.pid then
    os.execute(string.format("kill -TERM %d 2>/dev/null || kill -KILL %d 2>/dev/null", self.pid, self.pid))
    self.pid = nil
  end

  -- Cleanup temporary files
  os.remove(self.fifo_in)
  os.remove(self.fifo_out)
  os.remove(self.log_file)
  os.remove(self.pid_file)

  self.is_running = false
end

function McpRunner:get_stderr_log()
  local f = io.open(self.log_file, "r")
  if not f then
    return ""
  end
  local content = f:read("*a")
  f:close()
  return content or ""
end

return McpRunner
