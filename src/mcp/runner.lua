-- MCP Bass Machine - Ephemeral MCP Process Runner
-- Spawns MCP processes interactively via Linux FIFOs with zero permanent install.

local McpClient = require("mcp-bassmachine.mcp.client")
local term = require("mcp-bassmachine.utils.term")

local McpRunner = {}
McpRunner.__index = McpRunner

local runner_counter = 0

function McpRunner.new(command_str, env_vars, read_timeout_ms)
  local self = setmetatable({}, McpRunner)
  runner_counter = runner_counter + 1
  self.id = tostring(os.time()) .. "_" .. tostring(runner_counter) .. "_" .. term.random_hex(6)
  self.command = command_str
  self.env = env_vars or {}
  self.read_timeout_ms = read_timeout_ms or 30000
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

-- Adapts the native Win32 process handle to the file-like read/write/flush/close interface
-- McpClient expects. Reads poll with a deadline so a silent server can never freeze the TUI.
local function windows_pipe(proc, id, read_timeout_ms)
  local pending = ""
  local pipe = {}

  function pipe:write(data)
    local n = proc.write(id, data)
    return n ~= nil and self or nil
  end

  function pipe:flush()
    return true
  end

  function pipe:read(_fmt)
    local deadline = os.clock() + read_timeout_ms / 1000
    while true do
      local nl = pending:find("\n", 1, true)
      if nl then
        local line = pending:sub(1, nl - 1):gsub("\r$", "")
        pending = pending:sub(nl + 1)
        return line
      end
      local chunk = proc.read(id, 4096, 50)
      if chunk == nil then
        -- Child closed stdout: hand back any unterminated tail once, then EOF
        if #pending > 0 then
          local tail = pending
          pending = ""
          return tail
        end
        return nil
      end
      pending = pending .. chunk
      if #chunk == 0 and os.clock() >= deadline then
        return nil
      end
    end
  end

  function pipe:close()
    return true
  end

  return pipe
end

function McpRunner:start()
  if term.is_windows then
    local proc = term.win_proc
    if not proc then
      return false,
        "Native Windows helper (bin/windows/bass_wincon64.dll) not found or outdated; "
          .. "running MCP servers on Windows needs it. Reinstall or run scripts/build-wincon.sh."
    end

    -- cmd.exe resolves npx.cmd / .bat shims that CreateProcess alone cannot launch
    local cmdline = 'cmd.exe /d /s /c "' .. self.command .. '"'
    local id, pid = proc.spawn(cmdline, self.log_file)
    if not id then
      return false, "Failed to launch process: " .. self.command
    end
    self.win_id = id
    self.pid = pid
    self.in_handle = windows_pipe(proc, id, self.read_timeout_ms)
    self.out_handle = self.in_handle
    self.client = McpClient.new(self.in_handle, self.out_handle)
    self.is_running = true
    self.start_time = os.time()

    local ok, err = self.client:initialize()
    if not ok then
      local log = self:get_stderr_log()
      self:stop()
      return false, "Handshake failed: " .. tostring(err) .. (#log > 0 and (" | stderr: " .. log:sub(1, 300)) or "")
    end
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

  if self.win_id then
    -- Kills the whole job (cmd.exe -> npx -> node), not just the shell
    if term.win_proc then
      pcall(term.win_proc.kill, self.win_id)
    end
    self.win_id = nil
    self.pid = nil
  elseif self.pid then
    os.execute(string.format("kill -TERM %d 2>/dev/null || kill -KILL %d 2>/dev/null", self.pid, self.pid))
    self.pid = nil
  end

  -- Cleanup temporary files
  if not term.is_windows then
    os.remove(self.fifo_in)
    os.remove(self.fifo_out)
    os.remove(self.pid_file)
  end
  os.remove(self.log_file)

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
