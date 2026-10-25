-- MCP Bass Machine - Ephemeral MCP Process Runner
-- Spawns MCP processes interactively via Linux FIFOs with zero permanent install.

local McpClient = require("mcp-bassmachine.mcp.client")
local term = require("mcp-bassmachine.utils.term")

local McpRunner = {}
McpRunner.__index = McpRunner

local runner_counter = 0

function McpRunner.new(command_str, env_vars)
  local self = setmetatable({}, McpRunner)
  runner_counter = runner_counter + 1
  self.id = tostring(os.time()) .. "_" .. tostring(runner_counter) .. "_" .. term.random_hex(6)
  self.command = command_str
  self.env = env_vars or {}
  local tmp_dir = term.get_temp_dir()
  self.fifo_in = string.format("%s/mcp_bass_in_%s.fifo", tmp_dir, self.id)
  self.fifo_out = string.format("%s/mcp_bass_out_%s.fifo", tmp_dir, self.id)
  self.log_file = string.format("%s/mcp_bass_err_%s.log", tmp_dir, self.id)
  self.pid_file = string.format("%s/mcp_bass_pid_%s.pid", tmp_dir, self.id)
  self.pid = nil
  self.in_handle = nil
  self.out_handle = nil
  self.client = nil
  self.is_running = false
  self.start_time = 0
  return self
end

function McpRunner:start()
  if term.is_windows then
    -- On Windows, bidirectional two-way communication with subprocesses is supported
    -- via piped child processes; if full IPC is unavailable, return an informative error
    -- rather than hanging on POSIX FIFO creation.
    local pipe = term.safe_popen(self.command)
    if not pipe then
      return false, "Failed to launch process: " .. self.command
    end
    self.out_handle = pipe
    self.client = McpClient.new(nil, self.out_handle)
    self.is_running = true
    return true, self.client
  end

  -- Unix: Create FIFOs
  local q = term.shell_quote
  os.execute(string.format("mkfifo -m 600 %s %s 2>/dev/null", q(self.fifo_in), q(self.fifo_out)))

  -- Build environment prefix; names must be plain identifiers, values are shell-quoted
  local env_str = ""
  for k, v in pairs(self.env) do
    if type(k) == "string" and k:match("^[A-Za-z_][A-Za-z0-9_]*$") then
      env_str = env_str .. string.format("%s=%s ", k, q(tostring(v)))
    end
  end

  -- Pre-create log/pid files with mode 600 (redirects keep existing permissions), so the child's
  -- own umask is left untouched.
  for _, path in ipairs({ self.log_file, self.pid_file }) do
    local pf = term.open_private(path)
    if pf then
      pf:close()
    end
  end

  -- Spawn background process wrapped in subshell capturing PID.
  -- self.command is an intentional shell command line (e.g. "npx -y pkg"); only paths/env are escaped.
  local spawn_cmd = string.format(
    "( %s%s < %s > %s 2> %s & echo $! > %s ) 2>/dev/null",
    env_str,
    self.command,
    q(self.fifo_in),
    q(self.fifo_out),
    q(self.log_file),
    q(self.pid_file)
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
  -- Use "w+" on Unix FIFOs to prevent blocking if the reader is still initializing
  self.in_handle = io.open(self.fifo_in, "w+")
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
