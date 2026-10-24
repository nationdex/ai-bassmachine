-- MCP Bass Machine - High Performance ANSI Terminal Engine
-- Supports differential screen buffer rendering, animated bass visuals, and input loops.

local term = require("mcp-bassmachine.utils.term")

local Engine = {}
Engine.__index = Engine

local BASS_CHARS = { " ", " ", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

function Engine.new(fps)
  local self = setmetatable({}, Engine)
  self.fps = fps or 30
  self.running = false
  self.rows, self.cols = term.get_window_size()
  self.buffer = {}
  self.bass_bars = { 2, 4, 7, 5, 8, 6, 3, 5, 7, 4 }
  self.bass_phase = 0
  self:init_buffer(self.rows, self.cols)
  return self
end

function Engine:init_buffer(rows, cols)
  if rows and cols then
    self.rows = math.max(1, rows)
    self.cols = math.max(1, cols)
  else
    local r, c = term.get_window_size()
    self.rows = math.max(1, r)
    self.cols = math.max(1, c)
  end

  self.buffer = {}
  for r = 1, self.rows do
    self.buffer[r] = {}
    for c = 1, self.cols do
      self.buffer[r][c] = { char = " ", fg = term.palette.fg_primary, bg = term.palette.bg_dark }
    end
  end
end

function Engine:resize(new_r, new_c)
  new_r = math.max(1, new_r or self.rows)
  new_c = math.max(1, new_c or self.cols)
  if
    new_r ~= self.rows
    or new_c ~= self.cols
    or #self.buffer ~= new_r
    or (#self.buffer > 0 and #self.buffer[1] ~= new_c)
  then
    self:init_buffer(new_r, new_c)
    -- Clear entire terminal screen on dimension change to wipe orphaned line artifacts
    io.write("\27[2J\27[H")
    io.flush()
    return true
  end
  return false
end

function Engine:clear(bg)
  bg = bg or term.palette.bg_dark
  for r = 1, self.rows do
    local row_buf = self.buffer[r]
    if row_buf then
      for c = 1, self.cols do
        local cell = row_buf[c]
        if cell then
          cell.char = " "
          cell.fg = term.palette.fg_primary
          cell.bg = bg
        end
      end
    end
  end
end

function Engine:draw_text(row, col, text, fg, bg)
  if row < 1 or row > self.rows or col > self.cols then
    return
  end
  fg = fg or term.palette.fg_primary
  bg = bg or term.palette.bg_dark

  local c = col
  local i = 1
  local len = #text
  while i <= len and c <= self.cols do
    local b = text:byte(i)
    local ch
    if b < 128 then
      ch = text:sub(i, i)
      i = i + 1
    elseif b >= 192 and b <= 223 then
      ch = text:sub(i, i + 1)
      i = i + 2
    elseif b >= 224 and b <= 239 then
      ch = text:sub(i, i + 2)
      i = i + 3
    else
      ch = text:sub(i, i + 3)
      i = i + 4
    end

    if c >= 1 and c <= self.cols then
      self.buffer[row][c].char = ch
      self.buffer[row][c].fg = fg
      self.buffer[row][c].bg = bg
    end
    c = c + 1
  end
end

function Engine:draw_box(row, col, height, width, fg, bg, title)
  if height < 2 or width < 2 or row < 1 or row > self.rows or col < 1 or col > self.cols then
    return
  end

  fg = fg or term.palette.border
  bg = bg or term.palette.bg_dark

  -- Corners and edges
  local tl, tr, bl, br = "┌", "┐", "└", "┘"
  local h, v = "─", "│"

  self:draw_text(row, col, tl .. string.rep(h, width - 2) .. tr, fg, bg)
  local max_r = math.min(row + height - 2, self.rows)
  for r = row + 1, max_r do
    self:draw_text(r, col, v, fg, bg)
    self:draw_text(r, col + width - 1, v, fg, bg)
    -- Fill interior
    local row_buf = self.buffer[r]
    if row_buf then
      local max_c = math.min(col + width - 2, self.cols)
      for c = col + 1, max_c do
        local cell = row_buf[c]
        if cell then
          cell.char = " "
          cell.bg = bg
        end
      end
    end
  end

  if row + height - 1 <= self.rows then
    self:draw_text(row + height - 1, col, bl .. string.rep(h, width - 2) .. br, fg, bg)
  end

  if title and #title > 0 and width > 6 then
    local t_disp = " " .. title .. " "
    self:draw_text(row, col + 2, term.truncate(t_disp, width - 4), term.palette.fg_cyan, bg)
  end
end

function Engine:update_bass_animation()
  self.bass_phase = self.bass_phase + 0.2
  for i = 1, #self.bass_bars do
    local val = math.floor(4.5 + 3.5 * math.sin(self.bass_phase * (i * 0.45)))
    if val < 1 then
      val = 1
    elseif val > #BASS_CHARS then
      val = #BASS_CHARS
    end
    self.bass_bars[i] = val
  end
end

function Engine:get_bass_visualizer_str()
  local str = ""
  for _, bar_idx in ipairs(self.bass_bars) do
    str = str .. BASS_CHARS[bar_idx]
  end
  return str
end

function Engine:render()
  local out = {}
  table.insert(out, "\27[H") -- Move to home

  local last_fg = nil
  local last_bg = nil

  for r = 1, self.rows do
    local row_buf = self.buffer[r]
    if row_buf then
      for c = 1, self.cols do
        local cell = row_buf[c]
        if cell then
          if cell.fg ~= last_fg then
            table.insert(out, cell.fg)
            last_fg = cell.fg
          end
          if cell.bg ~= last_bg then
            table.insert(out, cell.bg)
            last_bg = cell.bg
          end
          table.insert(out, cell.char)
        else
          table.insert(out, " ")
        end
      end
    end
    if r < self.rows then
      table.insert(out, "\27[K\r\n")
    else
      table.insert(out, "\27[K")
    end
  end

  table.insert(out, "\27[J") -- Clear any remaining content below current bounds
  io.write(table.concat(out))
  io.flush()
end

return Engine
