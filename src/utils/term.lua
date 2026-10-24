-- MCP Bass Machine - Terminal & ANSI Engine
-- Robust raw mode, cross-platform sizing (Linux, macOS, Windows CMD / PowerShell 5.0 - 7+),
-- double-buffered rendering, and visual themes.

local term = {}

term.colors = {
  reset = "\27[0m",
  bold = "\27[1m",
  dim = "\27[2m",
  italic = "\27[3m",
  underline = "\27[4m",
  blink = "\27[5m",
  reverse = "\27[7m",
  hide_cursor = "\27[?25l",
  show_cursor = "\27[?25h",
  alt_screen_on = "\27[?1049h",
  alt_screen_off = "\27[?1049l",
  clear = "\27[2J\27[H",
  mouse_on = "\27[?1000h\27[?1002h\27[?1006h",
  mouse_off = "\27[?1000l\27[?1002l\27[?1006l",
}

-- Bass Machine Neon Color Palette
term.palette = {
  bg_dark = "\27[48;2;12;14;24m",
  bg_card = "\27[48;2;22;25;44m",
  bg_highlight = "\27[48;2;38;44;76m",
  fg_primary = "\27[38;2;240;244;255m",
  fg_muted = "\27[38;2;140;150;185m",
  fg_cyan = "\27[38;2;0;235;255m",
  fg_magenta = "\27[38;2;255;45;145m",
  fg_purple = "\27[38;2;165;85;255m",
  fg_neon_green = "\27[38;2;50;255;125m",
  fg_amber = "\27[38;2;255;185;35m",
  fg_red = "\27[38;2;255;70;70m",
  border = "\27[38;2;60;70;110m",
  border_focus = "\27[38;2;0;235;255m",
}

function term.rgb_fg(r, g, b)
  return string.format("\27[38;2;%d;%d;%dm", r, g, b)
end

function term.rgb_bg(r, g, b)
  return string.format("\27[48;2;%d;%d;%dm", r, g, b)
end

function term.move_to(row, col)
  return string.format("\27[%d;%dH", row, col)
end

local is_windows = (package.config:sub(1, 1) == "\\") or (os.getenv("OS") and os.getenv("OS"):match("Windows"))

local win_poll_key = nil
local win_init = nil
local win_cleanup = nil
local win_sleep = nil
local win_get_window_size = nil
local win_ffi = nil
local saved_win_in_mode = nil
local saved_win_out_mode = nil

if is_windows then
  -- 1. Try native ultra-low latency Win32 console helper DLL first
  local script_dir = ""
  local info = debug.getinfo(1, "S")
  if info and info.source and info.source:sub(1, 1) == "@" then
    local src_path = info.source:sub(2)
    script_dir = src_path:match("(.*[/\\])") or ""
  end

  local dll_paths = {
    "bin/windows/bass_wincon64.dll",
    "bin/windows/bass_wincon32.dll",
    script_dir .. "../../bin/windows/bass_wincon64.dll",
    script_dir .. "../../bin/windows/bass_wincon32.dll",
    script_dir .. "../bin/windows/bass_wincon64.dll",
    script_dir .. "../bin/windows/bass_wincon32.dll",
    "bass_wincon64.dll",
    "bass_wincon32.dll",
  }
  for _, path in ipairs(dll_paths) do
    local p_init = package.loadlib(path, "win_init")
    local p_poll = package.loadlib(path, "win_poll_key")
    local p_clean = package.loadlib(path, "win_cleanup")
    local p_sleep = package.loadlib(path, "win_sleep")
    local p_size = package.loadlib(path, "win_get_window_size")
    if p_init and p_poll and p_clean then
      win_init = p_init
      win_poll_key = p_poll
      win_cleanup = p_clean
      win_sleep = p_sleep
      win_get_window_size = p_size
      break
    end
  end

  -- 2. If DLL not found, check for LuaJIT FFI
  if not win_poll_key then
    local ok, ffi = pcall(require, "ffi")
    if ok and ffi then
      pcall(function()
        ffi.cdef([[
          typedef struct { short X; short Y; } COORD;
          typedef struct { short Left; short Top; short Right; short Bottom; } SMALL_RECT;
          typedef struct {
            COORD dwSize;
            COORD dwCursorPosition;
            unsigned short wAttributes;
            SMALL_RECT srWindow;
            COORD dwMaximumWindowSize;
          } CONSOLE_SCREEN_BUFFER_INFO;
          int _kbhit(void);
          int _getch(void);
          void Sleep(unsigned long dwMilliseconds);
          void* GetStdHandle(int nStdHandle);
          int GetConsoleMode(void* hConsoleHandle, unsigned int* lpMode);
          int SetConsoleMode(void* hConsoleHandle, unsigned int dwMode);
          int GetConsoleScreenBufferInfo(void* hConsoleOutput, CONSOLE_SCREEN_BUFFER_INFO* lpConsoleScreenBufferInfo);
        ]])
        win_ffi = ffi
      end)
    end
  end
end

local cached_rows = 24
local cached_cols = 80
local last_size_check = 0
local size_poll_interval = 0.5 -- Only query size every 500ms maximum to prevent CPU latency

function term.get_window_size(force)
  local now
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.gettime then
    now = socket.gettime()
  else
    now = os.time()
  end

  if not force and (now - last_size_check < size_poll_interval) then
    return cached_rows, cached_cols
  end

  last_size_check = now

  -- 1. Try environment variables first if available
  local lines = tonumber(os.getenv("LINES"))
  local columns = tonumber(os.getenv("COLUMNS"))
  if lines and columns and lines > 0 and columns > 0 then
    cached_rows = lines
    cached_cols = columns
    return cached_rows, cached_cols
  end

  -- 2. Windows-specific size query (Direct in-process Win32 query via native DLL or FFI)
  if is_windows then
    if win_get_window_size then
      local wok, r, c = pcall(win_get_window_size)
      if wok and r and c and r > 0 and c > 0 then
        cached_rows = r
        cached_cols = c
        return cached_rows, cached_cols
      end
    elseif win_ffi then
      local csbi = win_ffi.new("CONSOLE_SCREEN_BUFFER_INFO[1]")
      local hOut = win_ffi.C.GetStdHandle(-11)
      if win_ffi.C.GetConsoleScreenBufferInfo(hOut, csbi) ~= 0 then
        local r = csbi[0].srWindow.Bottom - csbi[0].srWindow.Top + 1
        local c = csbi[0].srWindow.Right - csbi[0].srWindow.Left + 1
        if r > 0 and c > 0 then
          cached_rows = r
          cached_cols = c
          return cached_rows, cached_cols
        end
      end
    end
    return cached_rows, cached_cols
  else
    -- 3. Unix: Query stty size via /dev/tty explicitly first so SSH and redirected streams report accurate dimensions
    local f = io.popen("stty size < /dev/tty 2>/dev/null || stty size 2>/dev/null", "r")
    if f then
      local out = f:read("*a")
      f:close()
      local r, c = out:match("(%d+)%s+(%d+)")
      if r and c then
        local nr, nc = tonumber(r), tonumber(c)
        if nr and nc and nr > 0 and nc > 0 then
          cached_rows = nr
          cached_cols = nc
          return cached_rows, cached_cols
        end
      end
    end
  end

  return cached_rows, cached_cols
end

function term.sleep(seconds)
  if is_windows then
    local ms = math.floor(seconds * 1000)
    if win_sleep then
      pcall(win_sleep, ms)
      return
    elseif win_ffi then
      pcall(win_ffi.C.Sleep, ms)
      return
    end
  end

  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.sleep then
    socket.sleep(seconds)
  else
    local ms = math.floor(seconds * 1000)
    if ms > 0 then
      if not is_windows then
        os.execute(string.format("sleep %f 2>/dev/null || sleep 1 2>/dev/null", seconds))
      end
    end
  end
end

local saved_stty = nil

function term.enter_raw_mode()
  if is_windows then
    if win_init then
      pcall(win_init)
    elseif win_ffi then
      pcall(function()
        local hIn = win_ffi.C.GetStdHandle(-10) -- STD_INPUT_HANDLE
        local hOut = win_ffi.C.GetStdHandle(-11) -- STD_OUTPUT_HANDLE
        local in_mode = win_ffi.new("unsigned int[1]")
        local out_mode = win_ffi.new("unsigned int[1]")
        if win_ffi.C.GetConsoleMode(hIn, in_mode) ~= 0 then
          saved_win_in_mode = in_mode[0]
          local raw_in = saved_win_in_mode
          local bit = rawget(_G, "bit")
          if bit and bit.band and bit.bnot then
            raw_in = bit.band(raw_in, bit.bnot(7))
          else
            raw_in = raw_in - (raw_in % 8)
          end
          win_ffi.C.SetConsoleMode(hIn, raw_in)
        end
        if win_ffi.C.GetConsoleMode(hOut, out_mode) ~= 0 then
          saved_win_out_mode = out_mode[0]
          local raw_out = saved_win_out_mode
          local bit = rawget(_G, "bit")
          if bit and bit.bor then
            raw_out = bit.bor(raw_out, 5)
          else
            raw_out = raw_out + 5
          end
          win_ffi.C.SetConsoleMode(hOut, raw_out)
        end
      end)
    else
      -- Git Bash / MSYS2 / Mintty fallback on Windows
      os.execute("stty raw -echo min 0 time 0 2>/dev/null")
    end
  else
    local f = io.popen("stty -g 2>/dev/null", "r")
    if f then
      saved_stty = f:read("*a")
      f:close()
      if saved_stty then
        saved_stty = saved_stty:gsub("%s+", "")
      end
    end
    os.execute("stty raw -echo min 0 time 0 2>/dev/null")
  end

  io.write(term.colors.alt_screen_on)
  io.write(term.colors.hide_cursor)
  io.flush()
end

function term.exit_raw_mode()
  io.write(term.colors.show_cursor)
  io.write(term.colors.alt_screen_off)
  io.flush()

  if is_windows then
    if win_cleanup then
      pcall(win_cleanup)
    elseif win_ffi and saved_win_in_mode then
      pcall(function()
        local hIn = win_ffi.C.GetStdHandle(-10)
        local hOut = win_ffi.C.GetStdHandle(-11)
        win_ffi.C.SetConsoleMode(hIn, saved_win_in_mode)
        if saved_win_out_mode then
          win_ffi.C.SetConsoleMode(hOut, saved_win_out_mode)
        end
      end)
    else
      os.execute("stty sane 2>/dev/null")
    end
  else
    if saved_stty and #saved_stty > 0 then
      os.execute("stty " .. saved_stty .. " 2>/dev/null")
    else
      os.execute("stty sane 2>/dev/null")
    end
  end
end

local input_buffer = {}

local function parse_keys_from_chunk(stream)
  local keys = {}
  local i = 1
  local len = #stream

  while i <= len do
    local c = stream:sub(i, i)
    if c == "\27" then
      if i + 1 > len then
        table.insert(keys, "esc")
        i = i + 1
      elseif stream:sub(i + 1, i + 1) == "[" then
        -- CSI escape sequence
        local seq_end = nil
        for j = i + 2, len do
          local b = stream:byte(j)
          if (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or b == 126 then
            seq_end = j
            break
          end
        end
        if seq_end then
          local seq = stream:sub(i + 2, seq_end)
          i = seq_end + 1
          if seq == "A" then
            table.insert(keys, "up")
          elseif seq == "B" then
            table.insert(keys, "down")
          elseif seq == "C" then
            table.insert(keys, "right")
          elseif seq == "D" then
            table.insert(keys, "left")
          elseif seq == "H" then
            table.insert(keys, "home")
          elseif seq == "F" then
            table.insert(keys, "end")
          elseif seq == "3~" then
            table.insert(keys, "delete")
          elseif seq == "5~" then
            table.insert(keys, "page_up")
          elseif seq == "6~" then
            table.insert(keys, "page_down")
          elseif seq:sub(1, 1) == "<" then
            local btn, col, row, act = seq:match("<(%d+);(%d+);(%d+)([Mm])")
            if btn and col and row then
              table.insert(keys, "mouse_" .. tostring(btn) .. "_" .. act)
            end
          else
            table.insert(keys, "esc_" .. seq)
          end
        else
          table.insert(keys, "esc")
          i = i + 1
        end
      elseif stream:sub(i + 1, i + 1) == "O" and i + 2 <= len then
        -- SS3 sequence (PowerShell / Windows Terminal arrow keys)
        local c3 = stream:sub(i + 2, i + 2)
        i = i + 3
        if c3 == "A" then
          table.insert(keys, "up")
        elseif c3 == "B" then
          table.insert(keys, "down")
        elseif c3 == "C" then
          table.insert(keys, "right")
        elseif c3 == "D" then
          table.insert(keys, "left")
        elseif c3 == "H" then
          table.insert(keys, "home")
        elseif c3 == "F" then
          table.insert(keys, "end")
        else
          table.insert(keys, "ss3_" .. c3)
        end
      else
        local c2 = stream:sub(i + 1, i + 1)
        i = i + 2
        if c2 == "\27" then
          table.insert(keys, "double_esc")
        else
          table.insert(keys, "alt_" .. c2)
        end
      end
    elseif c == "\0" or c == "\224" then
      -- Windows CONIN lead byte (0x00 or 0xE0) for arrows / nav keys in CMD & PowerShell
      if i + 1 <= len then
        local code = stream:byte(i + 1)
        i = i + 2
        if code == 72 then
          table.insert(keys, "up")
        elseif code == 80 then
          table.insert(keys, "down")
        elseif code == 77 then
          table.insert(keys, "right")
        elseif code == 75 then
          table.insert(keys, "left")
        elseif code == 71 then
          table.insert(keys, "home")
        elseif code == 79 then
          table.insert(keys, "end")
        elseif code == 73 then
          table.insert(keys, "page_up")
        elseif code == 81 then
          table.insert(keys, "page_down")
        elseif code == 83 then
          table.insert(keys, "delete")
        end
      else
        i = i + 1
      end
    elseif c == "\127" or c == "\8" then
      table.insert(keys, "backspace")
      i = i + 1
    elseif c == "\r" or c == "\n" then
      table.insert(keys, "enter")
      i = i + 1
    elseif c == "\t" then
      table.insert(keys, "tab")
      i = i + 1
    elseif c == "\3" then
      table.insert(keys, "ctrl_c")
      i = i + 1
    elseif c == "\4" then
      table.insert(keys, "ctrl_d")
      i = i + 1
    elseif c == "\18" then
      table.insert(keys, "ctrl_r")
      i = i + 1
    elseif c == "\17" then
      table.insert(keys, "ctrl_q")
      i = i + 1
    elseif c == "\14" then
      table.insert(keys, "ctrl_n")
      i = i + 1
    elseif c == "\16" then
      table.insert(keys, "ctrl_p")
      i = i + 1
    elseif c == "\1" then
      table.insert(keys, "ctrl_a")
      i = i + 1
    elseif c == "\5" then
      table.insert(keys, "ctrl_e")
      i = i + 1
    elseif c == " " then
      table.insert(keys, "space")
      i = i + 1
    else
      table.insert(keys, c)
      i = i + 1
    end
  end
  return keys
end

-- Read all currently available keys from terminal buffer in one batch
function term.read_keys()
  local keys = {}

  -- Return any keys already queued
  while #input_buffer > 0 do
    table.insert(keys, table.remove(input_buffer, 1))
  end

  if is_windows and win_poll_key then
    while true do
      local k = win_poll_key()
      if not k then
        break
      end
      table.insert(keys, k)
    end
    return keys
  end

  if is_windows then
    if win_ffi then
      -- 1. Windows with FFI (LuaJIT): instant non-blocking check & drain via _kbhit & _getch
      while win_ffi.C._kbhit() ~= 0 do
        local ch = win_ffi.C._getch()
        if ch == 0 or ch == 224 then
          local scan = win_ffi.C._getch()
          if scan == 72 then
            table.insert(keys, "up")
          elseif scan == 80 then
            table.insert(keys, "down")
          elseif scan == 75 then
            table.insert(keys, "left")
          elseif scan == 77 then
            table.insert(keys, "right")
          elseif scan == 71 then
            table.insert(keys, "home")
          elseif scan == 79 then
            table.insert(keys, "end")
          elseif scan == 73 then
            table.insert(keys, "page_up")
          elseif scan == 81 then
            table.insert(keys, "page_down")
          elseif scan == 83 then
            table.insert(keys, "delete")
          end
        elseif ch == 27 then
          local seq = ""
          while win_ffi.C._kbhit() ~= 0 do
            local next_c = win_ffi.C._getch()
            seq = seq .. string.char(next_c)
            if (next_c >= 65 and next_c <= 90) or (next_c >= 97 and next_c <= 122) or next_c == 126 then
              break
            end
          end
          if #seq > 0 then
            local parsed = parse_keys_from_chunk("\27" .. seq)
            for _, pk in ipairs(parsed) do
              table.insert(keys, pk)
            end
          else
            table.insert(keys, "esc")
          end
        elseif ch == 13 or ch == 10 then
          table.insert(keys, "enter")
        elseif ch == 8 or ch == 127 then
          table.insert(keys, "backspace")
        elseif ch == 9 then
          table.insert(keys, "tab")
        elseif ch == 3 then
          table.insert(keys, "ctrl_c")
        elseif ch == 4 then
          table.insert(keys, "ctrl_d")
        elseif ch == 18 then
          table.insert(keys, "ctrl_r")
        elseif ch == 17 then
          table.insert(keys, "ctrl_q")
        elseif ch == 32 then
          table.insert(keys, "space")
        elseif ch >= 32 and ch < 127 then
          table.insert(keys, string.char(ch))
        end
      end
      return keys
    else
      -- 2. Windows fallback without FFI (PUC Lua 5.1 - 5.4):
      -- Never call io.read(256) on Windows because fread will block waiting for 256 bytes!
      -- Read byte-by-byte using io.read(1) so single keystrokes return immediately.
      local b1 = io.read(1)
      if b1 and #b1 > 0 then
        if b1 == "\27" then
          local b2 = io.read(1)
          if b2 == "[" then
            local seq = ""
            while true do
              local b_next = io.read(1)
              if not b_next then
                break
              end
              seq = seq .. b_next
              local byte_val = b_next:byte()
              if (byte_val >= 65 and byte_val <= 90) or (byte_val >= 97 and byte_val <= 122) or byte_val == 126 then
                break
              end
            end
            local parsed = parse_keys_from_chunk("\27[" .. seq)
            for _, pk in ipairs(parsed) do
              table.insert(keys, pk)
            end
          elseif b2 == "O" then
            local b3 = io.read(1)
            local parsed = parse_keys_from_chunk("\27O" .. (b3 or ""))
            for _, pk in ipairs(parsed) do
              table.insert(keys, pk)
            end
          else
            table.insert(keys, "esc")
            if b2 then
              local parsed = parse_keys_from_chunk(b2)
              for _, pk in ipairs(parsed) do
                table.insert(keys, pk)
              end
            end
          end
        elseif b1 == "\0" or b1 == "\224" then
          local b2 = io.read(1)
          if b2 then
            local scan = b2:byte()
            if scan == 72 then
              table.insert(keys, "up")
            elseif scan == 80 then
              table.insert(keys, "down")
            elseif scan == 75 then
              table.insert(keys, "left")
            elseif scan == 77 then
              table.insert(keys, "right")
            elseif scan == 71 then
              table.insert(keys, "home")
            elseif scan == 79 then
              table.insert(keys, "end")
            elseif scan == 73 then
              table.insert(keys, "page_up")
            elseif scan == 81 then
              table.insert(keys, "page_down")
            elseif scan == 83 then
              table.insert(keys, "delete")
            end
          end
        else
          local parsed = parse_keys_from_chunk(b1)
          for _, pk in ipairs(parsed) do
            table.insert(keys, pk)
          end
        end
      end
      return keys
    end
  else
    -- 3. Unix (Linux / macOS): non-blocking read via stty min 0 time 0
    local chunk = io.read(256)
    if chunk and #chunk > 0 then
      local parsed = parse_keys_from_chunk(chunk)
      for _, k in ipairs(parsed) do
        table.insert(keys, k)
      end
    end
    return keys
  end
end

-- Read single key (legacy wrapper for backward compatibility)
function term.read_key()
  if #input_buffer > 0 then
    return table.remove(input_buffer, 1)
  end
  local keys = term.read_keys()
  if #keys > 0 then
    local first = keys[1]
    for idx = 2, #keys do
      table.insert(input_buffer, keys[idx])
    end
    return first
  end
  return nil
end

-- String utilities for UTF-8 terminal display
function term.strip_ansi(str)
  return str:gsub("\27%[[%d;]*[a-zA-Z]", "")
end

function term.visible_len(str)
  local clean = term.strip_ansi(str)
  return #clean
end

function term.pad_right(str, width)
  local vlen = term.visible_len(str)
  if vlen < width then
    return str .. string.rep(" ", width - vlen)
  else
    return str
  end
end

function term.truncate(str, max_width)
  local vlen = term.visible_len(str)
  if vlen <= max_width then
    return str
  end
  if max_width <= 3 then
    return str:sub(1, max_width)
  end
  return str:sub(1, max_width - 3) .. "..."
end

return term
