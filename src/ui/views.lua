-- MCP Bass Machine - TUI Views & Screens
-- Interactive screens for Marketplaces, Ephemeral Testing, AI Synthesis, History, and TOML Settings.

local term = require("mcp-bassmachine.utils.term")
local widgets = require("mcp-bassmachine.ui.widgets")
local json = require("mcp-bassmachine.utils.json")

local views = {}

-- 1. Marketplaces View
function views.render_marketplaces(engine, registry, state)
  local width = engine.cols
  local split_col = math.floor(width * 0.45)
  local main_h = engine.rows - 5

  -- Left: List of MCPs
  local box_title = "Marketplace Catalog"
  if state.search_query and #state.search_query > 0 then
    box_title = box_title .. " (Filter: " .. state.search_query .. ")"
  end
  engine:draw_box(4, 2, main_h, split_col - 2, term.palette.border, term.palette.bg_dark, box_title)

  local items = registry:search(state.search_query, state.category_filter, state.source_filter)
  state.marketplace_items = items

  if state.selected_mcp_idx > #items then
    state.selected_mcp_idx = math.max(1, #items)
  end

  widgets.draw_list(engine, items, state.selected_mcp_idx, 4, 2, main_h, split_col - 2, function(item, _)
    local tag = item.source and string.format("[%s]", item.source:upper()) or ""
    return string.format("%-12s %s", tag, item.name)
  end)

  -- Right: Detail Card of selected MCP
  local right_col = split_col + 1
  local right_w = width - right_col
  local selected = items[state.selected_mcp_idx]

  engine:draw_box(
    4,
    right_col,
    main_h,
    right_w,
    term.palette.border,
    term.palette.bg_dark,
    "Package Specs & Zero-Install Preview"
  )

  if selected then
    local r = 6
    engine:draw_text(r, right_col + 2, "Package:     " .. selected.name, term.palette.fg_cyan .. term.colors.bold)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Registry:    " .. (selected.source or "unknown"), term.palette.fg_primary)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Maintainer:  " .. (selected.author or "unknown"), term.palette.fg_muted)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Category:    " .. (selected.category or "General"), term.palette.fg_muted)
    r = r + 2

    engine:draw_text(r, right_col + 2, "Ephemeral Run Command (No Global Install):", term.palette.fg_amber)
    r = r + 1
    local full_cmd = selected.command .. " " .. table.concat(selected.args or {}, " ")
    engine:draw_text(r, right_col + 4, "$ " .. term.truncate(full_cmd, right_w - 6), term.palette.fg_neon_green)
    r = r + 2

    engine:draw_text(r, right_col + 2, "Description:", term.palette.fg_primary .. term.colors.bold)
    r = r + 1
    engine:draw_text(r, right_col + 4, term.truncate(selected.description or "", right_w - 6), term.palette.fg_muted)
    r = r + 2

    if selected.tags then
      engine:draw_text(r, right_col + 2, "Tags:        " .. table.concat(selected.tags, ", "), term.palette.fg_purple)
    end

    local bottom_row = 3 + main_h
    if bottom_row - 1 > r then
      engine:draw_text(
        bottom_row - 1,
        right_col + 2,
        term.truncate("Press [Enter] Ephemeral Run │ [I] Install to Agents", right_w - 4),
        term.palette.fg_magenta .. term.colors.bold
      )
    end
    if bottom_row > r then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [D] Remove from All Agents", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
  else
    engine:draw_text(
      6,
      right_col + 2,
      "No matching MCP found. Press [/] to search or [R] to refresh.",
      term.palette.fg_muted
    )
  end
end

-- 2. Test & Run Workspace View
function views.render_test_workspace(engine, active_runner, state)
  local width = engine.cols
  local main_h = engine.rows - 5
  local split_col = math.floor(width * 0.45)

  engine:draw_box(
    4,
    2,
    main_h,
    split_col - 2,
    term.palette.border,
    term.palette.bg_dark,
    "Discovered Tools & Capabilities"
  )

  if not active_runner or not active_runner.is_running then
    engine:draw_text(6, 4, "No active ephemeral MCP runner.", term.palette.fg_muted)
    engine:draw_text(8, 4, "Go to [1: Marketplaces] and press [Enter],", term.palette.fg_primary)
    engine:draw_text(9, 4, "or press [R] to run an ephemeral command.", term.palette.fg_cyan)
    return
  end

  local client = active_runner.client
  local tools = (client and client.tools) or {}
  state.active_tools = tools

  if #tools == 0 then
    engine:draw_text(6, 4, "Connected! No tools exposed or query pending...", term.palette.fg_amber)
  else
    widgets.draw_list(engine, tools, state.selected_tool_idx or 1, 4, 2, main_h, split_col - 2, function(tool, _)
      return string.format("⚡ %-16s", tool.name)
    end)
  end

  -- Right: Tool details and Call Inspector
  local right_col = split_col + 1
  local right_w = width - right_col
  local selected_tool = tools[state.selected_tool_idx or 1]

  engine:draw_box(
    4,
    right_col,
    main_h,
    right_w,
    term.palette.border,
    term.palette.bg_dark,
    "Tool Execution & Inspector"
  )

  if selected_tool then
    local r = 6
    engine:draw_text(r, right_col + 2, "Tool:        " .. selected_tool.name, term.palette.fg_cyan .. term.colors.bold)
    r = r + 1
    engine:draw_text(
      r,
      right_col + 2,
      "Description: " .. term.truncate(selected_tool.description or "None", right_w - 16),
      term.palette.fg_muted
    )
    r = r + 2

    engine:draw_text(r, right_col + 2, "Input Schema:", term.palette.fg_purple .. term.colors.bold)
    r = r + 1
    local schema_str = json.encode(selected_tool.inputSchema or {})
    engine:draw_text(r, right_col + 4, term.truncate(schema_str, right_w - 8), term.palette.fg_primary)
    r = r + 2

    engine:draw_text(r, right_col + 2, "Last Tool Call Result:", term.palette.fg_neon_green .. term.colors.bold)
    r = r + 1
    if state.last_tool_output then
      engine:draw_text(r, right_col + 4, term.truncate(state.last_tool_output, right_w - 8), term.palette.fg_primary)
    else
      engine:draw_text(r, right_col + 4, "(Ready to execute. Press [X] to call tool)", term.palette.fg_muted)
    end
  end
end

-- 3. AI Synthesizer View
function views.render_ai_synth(engine, config, state)
  local width = engine.cols
  local main_h = engine.rows - 5

  engine:draw_box(
    4,
    2,
    main_h,
    width - 4,
    term.palette.border,
    term.palette.bg_dark,
    "AI Tool Synthesis (ZenMux / OpenRouter / DeepSeek)"
  )

  local r = 6
  local prov = config:get("ai.default_provider", "zenmux")
  local model = config:get("ai.default_model", "deepseek/deepseek-v4.1-flash")

  engine:draw_text(r, 4, "Active AI Provider:  " .. prov:upper(), term.palette.fg_cyan .. term.colors.bold)
  r = r + 1
  engine:draw_text(r, 4, "Model:               " .. model, term.palette.fg_magenta .. term.colors.bold)
  r = r + 2

  engine:draw_text(r, 4, "Prompt Input:", term.palette.fg_primary .. term.colors.bold)
  r = r + 1
  local prompt_display = state.ai_prompt or "Say hello and test tool execution"
  engine:draw_text(r, 6, "> " .. prompt_display, term.palette.fg_neon_green)
  r = r + 2

  engine:draw_text(r, 4, "AI Synthesis Stream & Result:", term.palette.fg_amber .. term.colors.bold)
  r = r + 1

  if state.ai_response then
    local lines = {}
    for line in state.ai_response:gmatch("([^\r\n]+)") do
      table.insert(lines, line)
    end
    for idx, l in ipairs(lines) do
      if r + idx > main_h + 2 then
        break
      end
      engine:draw_text(r + idx, 6, term.truncate(l, width - 12), term.palette.fg_primary)
    end
  else
    engine:draw_text(
      r + 1,
      6,
      "Press [Enter] to run prompt synthesis through " .. model .. "...",
      term.palette.fg_muted
    )
  end
end

-- 4. Ephemeral History View (Zero Persistent Install)
function views.render_history(engine, history_mgr, state)
  local width = engine.cols
  local main_h = engine.rows - 5

  local title =
    string.format("Ephemeral MCP History (%d sessions) - [C] Clean All | [X] Clean Stale (>24h)", history_mgr:count())
  engine:draw_box(4, 2, main_h, width - 4, term.palette.border, term.palette.bg_dark, title)

  local items = history_mgr:list()
  state.history_items = items

  if #items == 0 then
    engine:draw_text(6, 4, "No MCP test history recorded yet.", term.palette.fg_muted)
    engine:draw_text(
      8,
      4,
      "All ephemeral MCP sessions appear here and can be cleaned anytime.",
      term.palette.fg_primary
    )
    return
  end

  widgets.draw_list(engine, items, state.selected_history_idx or 1, 4, 2, main_h, width - 4, function(item, _)
    local status_color = item.status == "ok" and "[OK]" or "[FAIL]"
    return string.format(
      "%-6s │ %-19s │ %-24s │ %-8s │ Tools: %d",
      status_color,
      item.time_formatted or "unknown",
      term.truncate(item.name or "session", 24),
      item.duration_ms and (tostring(item.duration_ms) .. "ms") or "-",
      item.tools_count or 0
    )
  end)
end

-- 5. Hybrid TOML Settings View
function views.render_settings(engine, config, state)
  local width = engine.cols
  local main_h = engine.rows - 5

  engine:draw_box(
    4,
    2,
    main_h,
    width - 4,
    term.palette.border,
    term.palette.bg_dark,
    "Hybrid TOML Configuration Editor (Live Reload)"
  )

  local settings_keys = {
    { key = "general.app_name", label = "App Name", type = "string" },
    { key = "general.auto_clean_history", label = "Auto-Clean History", type = "boolean" },
    { key = "general.max_history_entries", label = "Max History Entries", type = "number" },
    { key = "general.history_retention_hours", label = "Retention Hours", type = "number" },
    { key = "ui.theme", label = "UI Theme", type = "string" },
    { key = "ui.bass_meter", label = "Bass Meter Equalizer", type = "boolean" },
    { key = "ai.default_provider", label = "Default AI Provider", type = "string" },
    { key = "ai.default_model", label = "Default AI Model", type = "string" },
    { key = "ai.temperature", label = "Temperature", type = "number" },
    { key = "providers.zenmux.base_url", label = "ZenMux URL", type = "string" },
    { key = "providers.zenmux.default_model", label = "ZenMux Model", type = "string" },
    { key = "providers.openrouter.default_model", label = "OpenRouter Model", type = "string" },
  }

  state.settings_keys = settings_keys
  local sel_idx = state.selected_setting_idx or 1

  local r = 6
  for idx, s in ipairs(settings_keys) do
    local is_sel = (idx == sel_idx)
    local cur_val = config:get(s.key)
    local val_str = tostring(cur_val)
    if type(cur_val) == "string" and cur_val:match("^sk%-") then
      val_str = cur_val:sub(1, 10) .. "..." .. cur_val:sub(-6)
    end

    local fg = is_sel and (term.palette.fg_cyan .. term.colors.bold) or term.palette.fg_primary
    local bg = is_sel and term.palette.bg_highlight or term.palette.bg_dark

    local line = string.format(" %-28s │ %-40s ", s.label, val_str)
    engine:draw_text(r, 4, line, fg, bg)
    r = r + 1
  end

  if main_h > 4 then
    engine:draw_text(
      3 + main_h,
      4,
      term.truncate("Press [Space] toggle bool, [Enter] edit, [S] save TOML", width - 8),
      term.palette.fg_muted
    )
  end
end

-- 6. Environment Agent Sync View
function views.render_env_manager(engine, env_mgr, state)
  local width = engine.cols
  local main_h = engine.rows - 5
  local split_col = math.floor(width * 0.40)

  local targets = env_mgr:get_targets()
  state.env_targets = targets

  engine:draw_box(
    4,
    2,
    main_h,
    split_col - 2,
    term.palette.border,
    term.palette.bg_dark,
    "Detected AI Agent Environments"
  )

  local sel_target_idx = state.selected_target_idx or 1
  if sel_target_idx > #targets then
    sel_target_idx = #targets
  end

  widgets.draw_list(engine, targets, sel_target_idx, 4, 2, main_h, split_col - 2, function(t, _)
    local status = t.exists ~= false and "[ACTIVE]" or "[ABSENT]"
    return string.format("%-9s %s", status, t.name)
  end)

  -- Right: Installed MCPs in selected agent
  local right_col = split_col + 1
  local right_w = width - right_col
  local selected_target = targets[sel_target_idx]

  local summary = env_mgr:list_all()
  local target_info = summary[sel_target_idx]
  local servers = target_info and target_info.servers or {}

  local s_keys = {}
  for k in pairs(servers) do
    table.insert(s_keys, k)
  end
  table.sort(s_keys)
  state.current_target_servers = s_keys

  local right_title =
    string.format("Installed MCPs: %s (%d)", selected_target and selected_target.name or "Agent", #s_keys)
  engine:draw_box(4, right_col, main_h, right_w, term.palette.border, term.palette.bg_dark, right_title)

  if #s_keys == 0 then
    engine:draw_text(6, right_col + 2, "No MCP servers configured for this agent.", term.palette.fg_muted)
    engine:draw_text(
      8,
      right_col + 2,
      "Path: " .. term.truncate(selected_target.path, right_w - 10),
      term.palette.fg_primary
    )
    engine:draw_text(
      10,
      right_col + 2,
      "Go to [1: Marketplaces] and press [I] to install an MCP here,",
      term.palette.fg_cyan
    )
    engine:draw_text(11, right_col + 2, "or press [A] to add a custom MCP command.", term.palette.fg_cyan)
  else
    local max_visible = main_h - 7
    local sel_srv_idx = state.selected_env_server_idx or 1
    if sel_srv_idx > #s_keys then
      sel_srv_idx = #s_keys
    end

    local scroll_offset = 0
    if sel_srv_idx > max_visible then
      scroll_offset = sel_srv_idx - max_visible
    end

    for i = 1, max_visible do
      local idx = i + scroll_offset
      local sname = s_keys[idx]
      local r = 5 + i
      if sname then
        local is_sel = (idx == sel_srv_idx)
        local sspec = servers[sname]
        local cmd_preview = ""
        if sspec.url then
          cmd_preview = sspec.url
        elseif sspec.command then
          if type(sspec.command) == "table" then
            cmd_preview = table.concat(sspec.command, " ")
          else
            cmd_preview = tostring(sspec.command) .. " " .. table.concat(sspec.args or {}, " ")
          end
        end

        local line = string.format(" %-18s │ %s", sname, term.truncate(cmd_preview, right_w - 26))
        local fg = is_sel and (term.palette.fg_cyan .. term.colors.bold) or term.palette.fg_primary
        local bg = is_sel and term.palette.bg_highlight or term.palette.bg_dark
        engine:draw_text(r, right_col + 2, line, fg, bg)
      end
    end

    local bottom_row = 3 + main_h
    if bottom_row - 1 > 5 then
      engine:draw_text(
        bottom_row - 1,
        right_col + 2,
        term.truncate("Press [D] / [Del] to Remove from this Agent", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
    if bottom_row > 5 then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [U] to Purge from ALL Agents", right_w - 4),
        term.palette.fg_amber .. term.colors.bold
      )
    end
  end
end

return views
