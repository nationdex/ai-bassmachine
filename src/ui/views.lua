-- MCP Bass Machine - TUI Views & Screens
-- Interactive screens for Marketplaces, Ephemeral Testing, AI Synthesis, History, and TOML Settings.

local term = require("ai-bassmachine.utils.term")
local widgets = require("ai-bassmachine.ui.widgets")
local json = require("ai-bassmachine.utils.json")

local views = {}

-- 1. Marketplaces View
function views.render_marketplaces(engine, registry, env_mgr, state)
  local width = engine.cols
  local split_col = math.floor(width * 0.45)
  local main_h = engine.rows - 5

  -- Cache installed set for quick cross-reference
  local installed_set = {}
  local summary = env_mgr:list_all()
  for _, target in ipairs(summary) do
    if target.servers then
      for sname, _ in pairs(target.servers) do
        installed_set[sname:lower()] = true
        installed_set[sname:lower():gsub("[^%w]", "")] = true
      end
    end
  end

  local function is_installed(item)
    if not item then
      return false
    end
    local id_clean = item.id and item.id:lower():gsub("^mcp%-", "") or ""
    local name_clean = item.name and item.name:lower():gsub("[^%w]", "") or ""
    local base_clean = item.name and item.name:lower():match("^([^%s/]+)") or ""

    return installed_set[id_clean]
      or installed_set[name_clean]
      or installed_set[base_clean]
      or (item.command and installed_set[item.command:lower()])
      or (item.args and #item.args > 0 and installed_set[item.args[#item.args]:lower()])
  end

  -- Left: List of MCPs
  local box_title = "Marketplace Catalog"
  if state.search_query and #state.search_query > 0 then
    box_title = box_title .. " (Filter: " .. state.search_query .. ")"
  end
  engine:draw_box(4, 2, main_h, split_col - 2, term.palette.border, term.palette.bg_dark, box_title)

  local items = registry:search(state.search_query, state.category_filter, state.source_filter, state.pricing_filter)
  state.marketplace_items = items

  if state.selected_mcp_idx > #items then
    state.selected_mcp_idx = math.max(1, #items)
  end

  widgets.draw_list(engine, items, state.selected_mcp_idx, 4, 2, main_h, split_col - 2, function(item, _)
    local status_badge = is_installed(item) and "[INST]" or "[AVAIL]"
    local price_badge = (item.pricing == "Paid") and "[PAID]" or "[FREE]"
    return string.format("%-7s %-6s %s", status_badge, price_badge, item.name)
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
    local installed = is_installed(selected)
    local r = 6
    engine:draw_text(r, right_col + 2, "Package:     " .. selected.name, term.palette.fg_cyan .. term.colors.bold)
    r = r + 1
    local status_color = installed and term.palette.fg_neon_green or term.palette.fg_amber
    local status_text = installed and "INSTALLED (Registered in AI Agents)" or "NOT INSTALLED (Ephemeral Only)"
    engine:draw_text(r, right_col + 2, "Agent Status: " .. status_text, status_color .. term.colors.bold)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Registry:    " .. (selected.source or "unknown"), term.palette.fg_primary)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Maintainer:  " .. (selected.author or "unknown"), term.palette.fg_muted)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Category:    " .. (selected.category or "General"), term.palette.fg_muted)
    r = r + 1
    local price_str = (selected.pricing == "Paid") and "PAID / METERED (x402 / Micro-settlement / License)"
      or "FREE (Open-Source / Community)"
    local price_color = (selected.pricing == "Paid") and term.palette.fg_magenta or term.palette.fg_neon_green
    engine:draw_text(r, right_col + 2, "License:     " .. price_str, price_color .. term.colors.bold)
    r = r + 2

    engine:draw_text(r, right_col + 2, "Ephemeral Run Command (Zero Disk Footprint):", term.palette.fg_amber)
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
    if bottom_row - 3 > r then
      engine:draw_text(
        bottom_row - 3,
        right_col + 2,
        term.truncate("Press [Enter] Ephemeral Run │ [I] Quick Install", right_w - 4),
        term.palette.fg_magenta .. term.colors.bold
      )
    end
    if bottom_row - 2 > r then
      engine:draw_text(
        bottom_row - 2,
        right_col + 2,
        term.truncate("Press [C] Configure MCP (Env Vars / API Keys / Target Agent)", right_w - 4),
        term.palette.fg_cyan .. term.colors.bold
      )
    end
    if bottom_row - 1 > r then
      engine:draw_text(
        bottom_row - 1,
        right_col + 2,
        term.truncate("Press [D] / [Del] Remove from All Agents", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
    if bottom_row > r then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [/] Search │ [P] Filter Free/Paid │ [R] Sync", right_w - 4),
        term.palette.fg_muted
      )
    end
  else
    engine:draw_text(
      6,
      right_col + 2,
      "No matching MCP found. Press [/] to search or [R] to sync marketplaces.",
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
    engine:draw_text(9, 4, "or press [R] to spawn an ephemeral runner.", term.palette.fg_cyan)
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
      engine:draw_text(r, right_col + 4, "(Ready to execute. Press [Enter] / [X] to call tool)", term.palette.fg_muted)
    end
  end
end

-- 3. Dynamic Agent Skills View
function views.render_skills(engine, skill_mgr, state)
  local width = engine.cols
  local split_col = math.floor(width * 0.45)
  local main_h = engine.rows - 5

  local box_title = "Discovered Agent Skills"
  if state.skill_query and #state.skill_query > 0 then
    box_title = box_title .. " (Filter: " .. state.skill_query .. ")"
  end
  engine:draw_box(4, 2, main_h, split_col - 2, term.palette.border, term.palette.bg_dark, box_title)

  local all_skills = skill_mgr:list_all()
  local items = {}
  if state.skill_query and #state.skill_query > 0 then
    local q = state.skill_query:lower()
    for _, sk in ipairs(all_skills) do
      if sk.name:lower():find(q, 1, true) or sk.description:lower():find(q, 1, true) then
        table.insert(items, sk)
      end
    end
  else
    items = all_skills
  end
  state.skills_items = items

  local sel_idx = state.selected_skill_idx or 1
  if sel_idx > #items then
    sel_idx = math.max(1, #items)
    state.selected_skill_idx = sel_idx
  end

  if #items == 0 then
    engine:draw_text(6, 4, "No agent skills discovered.", term.palette.fg_muted)
    engine:draw_text(8, 4, "Press [A] to add/import a new skill,", term.palette.fg_cyan)
    engine:draw_text(9, 4, "or place a SKILL.md in ~/.agents/skills", term.palette.fg_muted)
  else
    widgets.draw_list(engine, items, sel_idx, 4, 2, main_h, split_col - 2, function(sk, _)
      local count = sk.installed_in and #sk.installed_in or 0
      local badge = string.format("[%d AGENTS]", count)
      return string.format("%-10s %s", badge, sk.name)
    end)
  end

  -- Right: Selected Skill Detail & Preview Card
  local right_col = split_col + 1
  local right_w = width - right_col
  local selected = items[sel_idx]

  engine:draw_box(
    4,
    right_col,
    main_h,
    right_w,
    term.palette.border,
    term.palette.bg_dark,
    "Skill Inspector (SKILL.md)"
  )

  if selected then
    local r = 6
    engine:draw_text(r, right_col + 2, "Skill:       " .. selected.name, term.palette.fg_cyan .. term.colors.bold)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Directory:   " .. (selected.dir_name or selected.name), term.palette.fg_primary)
    r = r + 1
    local in_str = (selected.installed_in and #selected.installed_in > 0) and table.concat(selected.installed_in, ", ")
      or "none"
    engine:draw_text(r, right_col + 2, "Agents:      " .. in_str, term.palette.fg_neon_green)
    r = r + 1
    engine:draw_text(
      r,
      right_col + 2,
      "Path:        " .. term.truncate(selected.path or "", right_w - 16),
      term.palette.fg_muted
    )
    r = r + 2

    engine:draw_text(r, right_col + 2, "Description:", term.palette.fg_primary .. term.colors.bold)
    r = r + 1
    engine:draw_text(
      r,
      right_col + 4,
      term.truncate(selected.description or "None", right_w - 8),
      term.palette.fg_muted
    )
    r = r + 2

    engine:draw_text(r, right_col + 2, "SKILL.md Content Preview:", term.palette.fg_amber .. term.colors.bold)
    r = r + 1
    local preview_text = selected.body or selected.raw or ""
    local max_lines = main_h - (r - 4) - 4
    local line_count = 0
    for line in preview_text:gmatch("[^\r\n]+") do
      if line_count < max_lines then
        engine:draw_text(r, right_col + 4, term.truncate(line, right_w - 8), term.palette.fg_primary)
        r = r + 1
        line_count = line_count + 1
      else
        break
      end
    end

    local bottom_row = 3 + main_h
    if bottom_row - 2 > r then
      engine:draw_text(
        bottom_row - 2,
        right_col + 2,
        term.truncate("Press [S] Sync/Broadcast to ALL Agents │ [A] Create Skill", right_w - 4),
        term.palette.fg_cyan .. term.colors.bold
      )
    end
    if bottom_row - 1 > r then
      engine:draw_text(
        bottom_row - 1,
        right_col + 2,
        term.truncate("Press [D] / [Del] Remove from Agent Environments", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
    if bottom_row > r then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [/] Filter Skills", right_w - 4),
        term.palette.fg_muted
      )
    end
  else
    engine:draw_text(6, right_col + 2, "Select a skill on the left or press [A] to add one.", term.palette.fg_muted)
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
    "AI Tool Synthesis (OpenCode-Style Hybrid Engine)"
  )

  local r = 6
  local prov = config:get("ai.default_provider", "zenmux")
  local model = config:get("ai.default_model", "deepseek/deepseek-v4.1-flash")

  engine:draw_text(
    r,
    4,
    "API Service: " .. prov:upper() .. "  [Press 'P' to switch service]",
    term.palette.fg_cyan .. term.colors.bold
  )
  r = r + 1
  engine:draw_text(
    r,
    4,
    "AI Model:    " .. model .. "  [Press 'M' to pick dynamically fetched model]",
    term.palette.fg_purple .. term.colors.bold
  )
  r = r + 2

  engine:draw_text(r, 4, "Prompt Input (Press [E] to edit prompt):", term.palette.fg_primary .. term.colors.bold)
  r = r + 1
  engine:draw_text(r, 6, "> " .. term.truncate(state.ai_prompt or "(none)", width - 12), term.palette.fg_amber)
  r = r + 2

  engine:draw_text(r, 4, "AI Synthesis Output:", term.palette.fg_neon_green .. term.colors.bold)
  r = r + 1
  if state.ai_response then
    local lines = {}
    for line in state.ai_response:gmatch("[^\r\n]+") do
      table.insert(lines, line)
    end
    for _, l in ipairs(lines) do
      if r < engine.rows - 2 then
        engine:draw_text(r, 6, term.truncate(l, width - 10), term.palette.fg_primary)
        r = r + 1
      end
    end
  else
    engine:draw_text(
      r,
      6,
      "(Press [Enter] to run synthesis query, [P] switch API service, [M] choose model, [E] edit prompt)",
      term.palette.fg_muted
    )
  end
end

-- 4. Ephemeral History View
function views.render_history(engine, history, state)
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
    "Ephemeral History (Zero-Install)"
  )

  local items = history:list()
  state.history_items = items

  if state.selected_history_idx > #items then
    state.selected_history_idx = math.max(1, #items)
  end

  if #items == 0 then
    engine:draw_text(6, 4, "No recent sessions. Clean state.", term.palette.fg_muted)
  else
    widgets.draw_list(engine, items, state.selected_history_idx, 4, 2, main_h, split_col - 2, function(item, _)
      local status_icon = (item.status == "ok") and "✓" or "✗"
      return string.format("%s %-14s [%s]", status_icon, item.name, item.time_formatted or "-")
    end)
  end

  -- Right: History session inspector
  local right_col = split_col + 1
  local right_w = width - right_col
  local selected = items[state.selected_history_idx]

  engine:draw_box(4, right_col, main_h, right_w, term.palette.border, term.palette.bg_dark, "Session Trace")

  if selected then
    local r = 6
    engine:draw_text(r, right_col + 2, "Session:     " .. selected.name, term.palette.fg_cyan .. term.colors.bold)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Timestamp:   " .. (selected.time_formatted or "-"), term.palette.fg_primary)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Status:      " .. (selected.status or "unknown"), term.palette.fg_neon_green)
    r = r + 1
    engine:draw_text(r, right_col + 2, "Tools Found: " .. tostring(selected.tools_count or 0), term.palette.fg_amber)
    r = r + 2

    engine:draw_text(r, right_col + 2, "Command Executed:", term.palette.fg_primary .. term.colors.bold)
    r = r + 1
    engine:draw_text(
      r,
      right_col + 4,
      "$ " .. term.truncate(selected.command or "", right_w - 6),
      term.palette.fg_muted
    )

    local bottom_row = 3 + main_h
    if bottom_row > r then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [Enter] Re-run │ [C] Clean All │ [X] Purge >24h", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
  end
end

-- 5. TOML Settings View
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
    "Hybrid TOML Configuration (bassmachine.toml)"
  )

  local settings_keys = {
    { key = "general.app_name", label = "App Name", type = "string" },
    { key = "general.auto_clean_history", label = "Auto Clean History", type = "boolean" },
    { key = "general.max_history_entries", label = "Max History Entries", type = "number" },
    { key = "general.history_retention_hours", label = "History Retention (h)", type = "number" },
    { key = "ui.theme", label = "Color Theme", type = "string" },
    { key = "ui.frame_rate", label = "TUI Target FPS", type = "number" },
    { key = "ui.bass_meter", label = "Bass Meter Animation", type = "boolean" },
    { key = "ai.default_provider", label = "Active AI Service", type = "provider_choice" },
    { key = "ai.default_model", label = "Active AI Model", type = "model_choice" },
    { key = "providers.api_key", label = "API Key (active service)", type = "api_key" },
    { key = "ai.temperature", label = "Sampling Temperature", type = "number" },
    { key = "ai.max_tokens", label = "Max Tokens", type = "number" },
    { key = "ai.request_timeout_seconds", label = "Timeout Seconds", type = "number" },
  }

  state.settings_keys = settings_keys
  local sel_idx = state.selected_setting_idx or 1

  local r = 6
  for idx, s in ipairs(settings_keys) do
    local is_sel = (idx == sel_idx)
    local cur_val = config:get(s.key)
    local val_str = tostring(cur_val)
    if s.type == "api_key" then
      -- Never render a stored key in full: masked value plus where it comes from
      local pid = config:get("ai.default_provider", "zenmux")
      local src = config:key_source(pid)
      local src_label = ({ env = "env var", file = "secrets file", none = "not set" })[src] or src
      val_str = pid == "ollama" and "(no key needed)" or (config:masked_api_key(pid) .. "  [" .. src_label .. "]")
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
      term.truncate(
        "Press [Enter]/[E] Edit Value │ [Space] Toggle Bool │ [S] Save TOML │ API Key row: [Enter] set, empty = remove",
        width - 8
      ),
      term.palette.fg_cyan .. term.colors.bold
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
    local max_visible = main_h - 8
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
    if bottom_row - 3 > 5 then
      engine:draw_text(
        bottom_row - 3,
        right_col + 2,
        term.truncate("Press [Enter] / [S] Broadcast & Install to ALL Agents", right_w - 4),
        term.palette.fg_cyan .. term.colors.bold
      )
    end
    if bottom_row - 2 > 5 then
      engine:draw_text(
        bottom_row - 2,
        right_col + 2,
        term.truncate("Press [A] Add Custom MCP to this Agent", right_w - 4),
        term.palette.fg_neon_green .. term.colors.bold
      )
    end
    if bottom_row - 1 > 5 then
      engine:draw_text(
        bottom_row - 1,
        right_col + 2,
        term.truncate("Press [D] / [Del] Remove from this Agent", right_w - 4),
        term.palette.fg_red .. term.colors.bold
      )
    end
    if bottom_row > 5 then
      engine:draw_text(
        bottom_row,
        right_col + 2,
        term.truncate("Press [U] Purge from ALL Agents", right_w - 4),
        term.palette.fg_amber .. term.colors.bold
      )
    end
  end
end

return views
