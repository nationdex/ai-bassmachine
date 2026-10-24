-- MCP Bass Machine - Terminal & ANSI Engine
-- Robust raw mode, screen sizing, double-buffered rendering, and visual themes.

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

local cached_rows = 24
local cached_cols = 80
local last_size_check = 0
local size_poll_interval = 0.5 -- Only spawn stty every 500ms maximum to prevent latency

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

  -- Query /dev/tty explicitly first so SSH and redirected standard streams report accurate window dimensions
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

  local lines = tonumber(os.getenv("LINES"))
  local columns = tonumber(os.getenv("COLUMNS"))
  if lines and columns and lines > 0 and columns > 0 then
    cached_rows = lines
    cached_cols = columns
    return cached_rows, cached_cols
  end

  return cached_rows, cached_cols
end

function term.sleep(seconds)
  local ok, socket = pcall(require, "socket")
  if ok and socket and socket.sleep then
    socket.sleep(seconds)
  else
    -- Fallback portable non-busy sleep via read timeout in raw mode or os.execute
    local ms = math.floor(seconds * 1000)
    if ms > 0 then
      os.execute(string.format("sleep %f 2>/dev/null || sleep 1 2>/dev/null", seconds))
    end
  end
end

local saved_stty = nil

function term.enter_raw_mode()
  local f = io.popen("stty -g 2>/dev/null", "r")
  if f then
    saved_stty = f:read("*a")
    f:close()
    if saved_stty then
      saved_stty = saved_stty:gsub("%s+", "")
    end
  end
  os.execute("stty raw -echo min 0 time 0 2>/dev/null")
  io.write(term.colors.alt_screen_on)
  io.write(term.colors.hide_cursor)
  io.write(term.colors.mouse_on)
  io.flush()
end

function term.exit_raw_mode()
  io.write(term.colors.mouse_off)
  io.write(term.colors.show_cursor)
  io.write(term.colors.alt_screen_off)
  io.flush()
  if saved_stty and #saved_stty > 0 then
    os.execute("stty " .. saved_stty .. " 2>/dev/null")
  else
    os.execute("stty sane 2>/dev/null")
  end
end

-- Read a single key or escape sequence non-blockingly
function term.read_key()
  local c = io.read(1)
  if not c then
    return nil
  end

  if c == "\27" then
    local c2 = io.read(1)
    if not c2 then
      return "esc"
    end
    if c2 == "[" then
      local seq = ""
      while true do
        local cn = io.read(1)
        if not cn then
          break
        end
        seq = seq .. cn
        if (cn >= "A" and cn <= "Z") or cn == "~" or (cn >= "a" and cn <= "z") then
          break
        end
      end
      if seq == "A" then
        return "up"
      elseif seq == "B" then
        return "down"
      elseif seq == "C" then
        return "right"
      elseif seq == "D" then
        return "left"
      elseif seq == "H" then
        return "home"
      elseif seq == "F" then
        return "end"
      elseif seq == "3~" then
        return "delete"
      elseif seq == "5~" then
        return "page_up"
      elseif seq == "6~" then
        return "page_down"
      elseif seq:sub(1, 1) == "<" then
        -- SGR mouse event
        local btn, col, row, act = seq:match("<(%d+);(%d+);(%d+)([Mm])")
        if btn and col and row then
          return "mouse", tonumber(btn), tonumber(col), tonumber(row), act
        end
      end
      return "esc_" .. seq
    elseif c2 == "\27" then
      return "double_esc"
    else
      return "alt_" .. c2
    end
  elseif c == "\127" or c == "\8" then
    return "backspace"
  elseif c == "\r" or c == "\n" then
    return "enter"
  elseif c == "\t" then
    return "tab"
  elseif c == "\3" then
    return "ctrl_c"
  elseif c == "\4" then
    return "ctrl_d"
  elseif c == "\18" then
    return "ctrl_r"
  elseif c == "\17" then
    return "ctrl_q"
  elseif c == "\14" then
    return "ctrl_n"
  elseif c == "\16" then
    return "ctrl_p"
  elseif c == "\1" then
    return "ctrl_a"
  elseif c == "\5" then
    return "ctrl_e"
  elseif c == " " then
    return "space"
  end

  return c
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
