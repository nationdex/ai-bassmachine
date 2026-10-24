-- MCP Bass Machine - TUI Widgets
-- Component library for tabs, lists, details panels, status bars, modals, and bass visualizers.

local term = require("mcp-bassmachine.utils.term")

local widgets = {}

function widgets.draw_header(engine, active_tab_name, active_model, bass_meter_enabled)
  local width = engine.cols
  local bg = term.palette.bg_card

  -- Background fill for header row 1 and 2
  for c = 1, width do
    engine.buffer[1][c].char = " "
    engine.buffer[1][c].bg = bg
    engine.buffer[2][c].char = " "
    engine.buffer[2][c].bg = bg
  end

  local title = " 🎛  MCP BASS MACHINE "
  engine:draw_text(1, 2, title, term.palette.fg_cyan .. term.colors.bold, bg)

  if bass_meter_enabled ~= false then
    local bass_str = " [" .. engine:get_bass_visualizer_str() .. "] "
    engine:draw_text(1, #title + 3, bass_str, term.palette.fg_magenta .. term.colors.bold, bg)
  end

  local right_info = string.format(" AI: %s │ Tab: %s ", active_model or "Offline", active_tab_name or "Home")
  local right_col = math.max(1, width - #right_info - 1)
  engine:draw_text(1, right_col, right_info, term.palette.fg_muted, bg)

  -- Subtle divider line
  for c = 1, width do
    engine.buffer[2][c].char = "─"
    engine.buffer[2][c].fg = term.palette.border
    engine.buffer[2][c].bg = term.palette.bg_dark
  end
end

function widgets.draw_tab_bar(engine, tabs, active_idx, row)
  row = row or 3
  local col = 2
  for idx, name in ipairs(tabs) do
    local is_active = (idx == active_idx)
    local label = string.format(" %d:%s ", idx, name)
    local fg = is_active and (term.palette.fg_cyan .. term.colors.bold) or term.palette.fg_muted
    local bg = is_active and term.palette.bg_highlight or term.palette.bg_card
    engine:draw_text(row, col, label, fg, bg)
    col = col + #label + 1
  end
end

function widgets.draw_status_bar(engine, message, hotkeys)
  local row = engine.rows
  local width = engine.cols
  local bg = term.palette.bg_card

  for c = 1, width do
    engine.buffer[row][c].char = " "
    engine.buffer[row][c].bg = bg
  end

  if message and #message > 0 then
    engine:draw_text(row, 2, message, term.palette.fg_neon_green, bg)
  end

  if hotkeys and #hotkeys > 0 then
    local hk_col = math.max(1, width - #hotkeys - 2)
    engine:draw_text(row, hk_col, hotkeys, term.palette.fg_muted, bg)
  end
end

function widgets.draw_list(engine, items, selected_idx, top_row, left_col, height, width, format_fn)
  local max_visible = height - 2
  local scroll_offset = 0
  if selected_idx > max_visible then
    scroll_offset = selected_idx - max_visible
  end

  for i = 1, max_visible do
    local item_idx = i + scroll_offset
    local item = items[item_idx]
    local r = top_row + i
    if item then
      local is_selected = (item_idx == selected_idx)
      local line_text = format_fn(item, is_selected)
      local fg = is_selected and (term.palette.fg_cyan .. term.colors.bold) or term.palette.fg_primary
      local bg = is_selected and term.palette.bg_highlight or term.palette.bg_dark

      -- Fill line background
      for c = left_col + 1, left_col + width - 2 do
        engine.buffer[r][c].char = " "
        engine.buffer[r][c].bg = bg
      end

      local truncated = term.truncate(line_text, width - 4)
      engine:draw_text(r, left_col + 2, truncated, fg, bg)
    else
      for c = left_col + 1, left_col + width - 2 do
        engine.buffer[r][c].char = " "
        engine.buffer[r][c].bg = term.palette.bg_dark
      end
    end
  end
end

function widgets.draw_modal_input(engine, title, prompt, value, cursor_pos)
  local box_w = math.min(70, engine.cols - 4)
  local box_h = 7
  local top_r = math.floor((engine.rows - box_h) / 2)
  local left_c = math.floor((engine.cols - box_w) / 2)

  local bg = term.palette.bg_card
  local fg_border = term.palette.border_focus

  engine:draw_box(top_r, left_c, box_h, box_w, fg_border, bg, title)

  engine:draw_text(top_r + 2, left_c + 3, prompt, term.palette.fg_cyan .. term.colors.bold, bg)

  local input_w = box_w - 6
  local display_val = value or ""
  local truncated_val = term.truncate(display_val, input_w - 2)

  -- Input box field background
  local input_r = top_r + 3
  local input_bg = term.palette.bg_dark
  for c = left_c + 3, left_c + box_w - 4 do
    engine.buffer[input_r][c].char = " "
    engine.buffer[input_r][c].bg = input_bg
  end

  engine:draw_text(input_r, left_c + 4, truncated_val, term.palette.fg_neon_green, input_bg)

  -- Draw cursor block
  local cur_col = left_c + 4 + math.min(#truncated_val, cursor_pos or #truncated_val)
  if cur_col <= left_c + box_w - 4 and engine.buffer[input_r] and engine.buffer[input_r][cur_col] then
    local cur_cell = engine.buffer[input_r][cur_col]
    local char_under = cur_cell.char ~= "" and cur_cell.char or " "
    engine:draw_text(input_r, cur_col, char_under, term.palette.bg_dark, term.palette.fg_cyan)
  end

  local hint = "[Enter] Confirm │ [Esc] Cancel │ [Backspace] Delete"
  engine:draw_text(top_r + 5, left_c + 3, term.truncate(hint, box_w - 6), term.palette.fg_muted, bg)
end

return widgets
