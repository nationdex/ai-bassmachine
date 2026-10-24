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
  self:init_buffer()
  return self
end

function Engine:init_buffer()
  self.rows, self.cols = term.get_window_size()
  self.buffer = {}
  for r = 1, self.rows do
    self.buffer[r] = {}
    for c = 1, self.cols do
      self.buffer[r][c] = { char = " ", fg = term.palette.fg_primary, bg = term.palette.bg_dark }
    end
  end
end

function Engine:clear(bg)
  bg = bg or term.palette.bg_dark
  for r = 1, self.rows do
    for c = 1, self.cols do
      self.buffer[r][c].char = " "
      self.buffer[r][c].fg = term.palette.fg_primary
      self.buffer[r][c].bg = bg
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
  fg = fg or term.palette.border
  bg = bg or term.palette.bg_dark

  -- Corners and edges
  local tl, tr, bl, br = "┌", "┐", "└", "┘"
  local h, v = "─", "│"

  self:draw_text(row, col, tl .. string.rep(h, width - 2) .. tr, fg, bg)
  for r = row + 1, row + height - 2 do
    self:draw_text(r, col, v, fg, bg)
    self:draw_text(r, col + width - 1, v, fg, bg)
    -- Fill interior
    for c = col + 1, col + width - 2 do
      self.buffer[r][c].char = " "
      self.buffer[r][c].bg = bg
    end
  end
  self:draw_text(row + height - 1, col, bl .. string.rep(h, width - 2) .. br, fg, bg)

  if title and #title > 0 then
    local t_disp = " " .. title .. " "
    self:draw_text(row, col + 2, t_disp, term.palette.fg_cyan, bg)
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
    for c = 1, self.cols do
      local cell = self.buffer[r][c]
      if cell.fg ~= last_fg then
        table.insert(out, cell.fg)
        last_fg = cell.fg
      end
      if cell.bg ~= last_bg then
        table.insert(out, cell.bg)
        last_bg = cell.bg
      end
      table.insert(out, cell.char)
    end
    if r < self.rows then
      table.insert(out, "\r\n")
    end
  end

  io.write(table.concat(out))
  io.flush()
end

return Engine
