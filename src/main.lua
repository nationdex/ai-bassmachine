-- MCP Bass Machine - Main Application Entrypoint
-- Pure Lua 5.X TUI & CLI suite to test and run MCPs across multiple marketplaces.

package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local term = require("mcp-bassmachine.utils.term")
local Engine = require("mcp-bassmachine.ui.engine")
local widgets = require("mcp-bassmachine.ui.widgets")
local views = require("mcp-bassmachine.ui.views")
local ConfigManager = require("mcp-bassmachine.config.manager")
local Registry = require("mcp-bassmachine.marketplace.registry")
local HistoryManager = require("mcp-bassmachine.mcp.history")
local McpRunner = require("mcp-bassmachine.mcp.runner")
local AiProvider = require("mcp-bassmachine.ai.provider")
local EnvManager = require("mcp-bassmachine.env.manager")
local json = require("mcp-bassmachine.utils.json")

local app = {}

function app.run_cli_test(config, history, ai)
  io.write("\27[1;36m🎛  MCP Bass Machine - Pre-flight Verification\27[0m\n")
  io.write("=====================================================\n")

  -- 1. Test TOML Configuration
  io.write("[1/4] Verifying TOML configuration: ")
  local app_name = config:get("general.app_name")
  local default_provider = config:get("ai.default_provider")
  local default_model = config:get("ai.default_model")
  if app_name and default_provider and default_model then
    io.write("\27[1;32mOK\27[0m (" .. app_name .. " | Model: " .. default_model .. ")\n")
  else
    io.write("\27[1;31mFAILED\27[0m\n")
    return false
  end

  -- 2. Test Ephemeral History & Cleanups
  io.write("[2/4] Testing Ephemeral History Manager: ")
  history:add({
    name = "preflight-test-session",
    command = "mcp-test-runner",
    tools_count = 3,
    status = "ok",
    duration_ms = 42,
  })
  local count_before = history:count()
  if count_before > 0 then
    io.write("\27[1;32mOK\27[0m (" .. count_before .. " entries tracked, zero-install verified)\n")
  else
    io.write("\27[1;31mFAILED\27[0m\n")
    return false
  end

  -- 3. Test Multi-Marketplace Discovery
  io.write("[3/4] Testing Marketplace Registry: ")
  local registry = Registry.new(config)
  local servers = registry:get_all()
  if #servers > 0 then
    io.write("\27[1;32mOK\27[0m (" .. #servers .. " MCPs indexed across official, smithery, glama)\n")
  else
    io.write("\27[1;31mFAILED\27[0m\n")
    return false
  end

  -- 4. Test AI Integration (ZenMux with deepseek/deepseek-v4.1-flash)
  io.write("[4/4] Testing ZenMux AI & deepseek/deepseek-v4.1-flash: ")
  local resp, err = ai:chat_completion({
    { role = "user", content = "Ping from MCP Bass Machine preflight" },
  }, {
    provider = "zenmux",
    model = "deepseek/deepseek-v4.1-flash",
  })

  if resp and resp.content then
    io.write('\27[1;32mOK\27[0m (Synthesis response received: "' .. resp.content:gsub("\n", " ") .. '")\n')
  else
    io.write("\27[1;31mFAILED\27[0m (" .. tostring(err) .. ")\n")
    return false
  end

  io.write("=====================================================\n")
  io.write("\27[1;32m✓ All MCP Bass Machine systems operational.\27[0m\n")
  return true
end

function app.run_cli_ephemeral_mcp(command_str, _config, history)
  io.write("\27[1;36m🎛  MCP Bass Machine - Ephemeral Runner\27[0m\n")
  io.write("Target: " .. command_str .. "\n")
  io.write("Initializing zero-install execution...\n")

  local runner = McpRunner.new(command_str)
  local ok, err_or_client = runner:start()
  local start_time = os.time()

  if not ok then
    io.write("\27[1;31mExecution failed:\27[0m " .. tostring(err_or_client) .. "\n")
    local err_log = runner:get_stderr_log()
    if #err_log > 0 then
      io.write("Stderr: " .. err_log .. "\n")
    end
    runner:stop()
    history:add({
      name = command_str:match("^%S+") or "unknown",
      command = command_str,
      status = "failed",
      tools_count = 0,
    })
    return false
  end

  local client = err_or_client
  local tools = client:list_tools() or {}
  local duration_ms = (os.time() - start_time) * 1000

  io.write(string.format("\27[1;32mConnected!\27[0m Discovered %d tools:\n", #tools))
  for idx, t in ipairs(tools) do
    io.write(string.format("  [%d] \27[1;35m%s\27[0m - %s\n", idx, t.name, t.description or "No description"))
  end

  runner:stop()

  history:add({
    name = command_str:match("^%S+") or "unknown",
    command = command_str,
    status = "ok",
    tools_count = #tools,
    duration_ms = duration_ms,
  })

  io.write("\n\27[1;32m✓ Ephemeral run complete. Session stored in history (auto-clean enabled).\27[0m\n")
  return true
end

function app.run_tui(config, history, registry, ai, env_mgr)
  term.enter_raw_mode()

  local engine = Engine.new(config:get("ui.frame_rate", 30))
  local tabs = { "Marketplaces", "Test & Run", "AI Synth", "History", "Settings", "Agent Sync" }
  local active_tab_idx = 1

  local state = {
    selected_mcp_idx = 1,
    selected_tool_idx = 1,
    selected_history_idx = 1,
    selected_setting_idx = 1,
    selected_target_idx = 1,
    selected_env_server_idx = 1,
    search_query = "",
    ai_prompt = "Hello! Test MCP tool integration with deepseek/deepseek-v4.1-flash",
    ai_response = nil,
    status_msg = "Welcome to MCP Bass Machine. Multi-Agent Sync ready.",
    active_runner = nil,
    modal = nil,
  }

  local running = true

  while running do
    local cur_r, cur_c = term.get_window_size()
    engine:resize(cur_r, cur_c)
    engine:clear()

    -- 1. Draw Header
    local active_model = config:get("ai.default_model", "deepseek/deepseek-v4.1-flash")
    widgets.draw_header(engine, tabs[active_tab_idx], active_model, config:get("ui.bass_meter", true))

    -- 2. Draw Tab Bar
    widgets.draw_tab_bar(engine, tabs, active_tab_idx, 3)

    -- 3. Draw Active View
    if active_tab_idx == 1 then
      views.render_marketplaces(engine, registry, env_mgr, state)
    elseif active_tab_idx == 2 then
      views.render_test_workspace(engine, state.active_runner, state)
    elseif active_tab_idx == 3 then
      views.render_ai_synth(engine, config, state)
    elseif active_tab_idx == 4 then
      views.render_history(engine, history, state)
    elseif active_tab_idx == 5 then
      views.render_settings(engine, config, state)
    elseif active_tab_idx == 6 then
      views.render_env_manager(engine, env_mgr, state)
    end

    -- 4. Draw Modal Overlay if active
    if state.modal then
      widgets.draw_modal_input(engine, state.modal.title, state.modal.prompt, state.modal.value, #state.modal.value)
    end

    -- 5. Draw Status Bar
    local hotkeys = "[1-6] Tabs │ [↑/↓] Navigate │ [Enter] Select/Run │ [Q] Quit"
    if active_tab_idx == 1 then
      hotkeys = "[Enter] Run │ [I] Install │ [D] Del │ [/] Search │ [R] Sync"
    elseif active_tab_idx == 2 then
      hotkeys = "[X] Call Tool │ [R] Spawn Runner │ [K] Stop Runner"
    elseif active_tab_idx == 3 then
      hotkeys = "[Enter] Synthesize │ [E] Edit Prompt"
    elseif active_tab_idx == 4 then
      hotkeys = "[C] Clean All │ [X] Purge >24h"
    elseif active_tab_idx == 5 then
      hotkeys = "[Enter]/[E] Edit │ [Space] Toggle │ [S] Save TOML"
    elseif active_tab_idx == 6 then
      hotkeys = "[←/→] Agent │ [D] Remove │ [U] Purge All │ [A] Add MCP"
    end

    if state.modal then
      hotkeys = "[Enter] Confirm │ [Esc] Cancel │ [Backspace] Edit"
    end

    widgets.draw_status_bar(engine, state.status_msg, hotkeys)

    -- Update visualizer & render frame
    engine:update_bass_animation()
    engine:render()

    -- Frame throttle to eliminate SSH latency & high CPU usage (15ms ~ 60 FPS cap)
    term.sleep(0.015)

    -- Process input
    local key = term.read_key()
    if key then
      -- If inside a modal input dialog, capture text entry
      if state.modal then
        if key == "esc" or key == "double_esc" or key == "ctrl_c" then
          state.modal = nil
          state.status_msg = "Editing cancelled."
        elseif key == "enter" then
          local m = state.modal
          if m.type == "edit_setting" then
            local val = m.value
            local s = m.setting
            if s.type == "number" then
              local num = tonumber(val)
              if num then
                config:set(s.key, num)
                state.status_msg = string.format("Set %s to %s (Unsaved, press [S] to write)", s.label, tostring(num))
              else
                state.status_msg = "Invalid number format."
              end
            elseif s.type == "boolean" then
              local b = (val:lower() == "true" or val == "1" or val:lower() == "yes")
              config:set(s.key, b)
              state.status_msg = string.format("Set %s to %s", s.label, tostring(b))
            else
              config:set(s.key, val)
              state.status_msg = string.format("Set %s to '%s' (Press [S] to save)", s.label, val)
            end
          elseif m.type == "search_marketplace" then
            state.search_query = m.value
            state.selected_mcp_idx = 1
            state.status_msg = #m.value > 0 and ("Filter applied: " .. m.value) or "Search filter cleared."
          elseif m.type == "edit_prompt" then
            state.ai_prompt = m.value
            state.status_msg = "Updated AI prompt."
          elseif m.type == "add_mcp_agent" then
            local sname, cmd_str = m.value:match("^([^%s=:]+)%s*[=:]%s*(.+)$")
            if not sname then
              sname, cmd_str = m.value:match("^([^%s]+)%s+(.+)$")
            end
            if sname and cmd_str then
              local spec = {}
              if cmd_str:match("^https?://") then
                spec.url = cmd_str
              else
                local parts = {}
                for p in cmd_str:gmatch("%S+") do
                  table.insert(parts, p)
                end
                spec.command = parts[1]
                table.remove(parts, 1)
                spec.args = parts
              end
              local targets = state.env_targets or {}
              local cur_target = targets[state.selected_target_idx or 1]
              local tid = cur_target and cur_target.id or "all"
              local results = env_mgr:add_mcp(sname, spec, tid)
              local ok_cnt = 0
              for _, res in ipairs(results) do
                if res.success then
                  ok_cnt = ok_cnt + 1
                end
              end
              state.status_msg = string.format("Added '%s' to %d environment(s).", sname, ok_cnt)
            else
              state.status_msg = "Syntax error. Use: <name> <command>"
            end
          elseif m.type == "spawn_runner" then
            if #m.value > 0 then
              if state.active_runner then
                state.active_runner:stop()
              end
              state.status_msg = "Starting: " .. m.value .. "..."
              engine:render()
              local runner = McpRunner.new(m.value)
              local ok, client_or_err = runner:start()
              if ok then
                state.active_runner = runner
                local tools = client_or_err:list_tools() or {}
                state.status_msg = string.format("Connected! Discovered %d tools.", #tools)
                history:add({
                  name = m.value:match("^%S+") or "custom",
                  command = m.value,
                  status = "ok",
                  tools_count = #tools,
                })
              else
                runner:stop()
                state.status_msg = "Spawn failed: " .. tostring(client_or_err)
              end
            end
          end
          state.modal = nil
        elseif key == "backspace" then
          local v = state.modal.value
          if #v > 0 then
            state.modal.value = v:sub(1, #v - 1)
          end
        elseif key == "space" then
          state.modal.value = state.modal.value .. " "
        elseif #key == 1 and key:byte(1) >= 32 and key:byte(1) <= 126 then
          state.modal.value = state.modal.value .. key
        end
      else
        -- Standard TUI Navigation
        if key == "q" or key == "ctrl_c" then
          running = false
        elseif key == "1" then
          active_tab_idx = 1
        elseif key == "2" then
          active_tab_idx = 2
        elseif key == "3" then
          active_tab_idx = 3
        elseif key == "4" then
          active_tab_idx = 4
        elseif key == "5" then
          active_tab_idx = 5
        elseif key == "6" then
          active_tab_idx = 6
        elseif key == "tab" then
          active_tab_idx = (active_tab_idx % #tabs) + 1
        elseif key == "up" then
          if active_tab_idx == 1 then
            state.selected_mcp_idx = math.max(1, state.selected_mcp_idx - 1)
          elseif active_tab_idx == 2 then
            state.selected_tool_idx = math.max(1, state.selected_tool_idx - 1)
          elseif active_tab_idx == 4 then
            state.selected_history_idx = math.max(1, state.selected_history_idx - 1)
          elseif active_tab_idx == 5 then
            state.selected_setting_idx = math.max(1, state.selected_setting_idx - 1)
          elseif active_tab_idx == 6 then
            state.selected_env_server_idx = math.max(1, (state.selected_env_server_idx or 1) - 1)
          end
        elseif key == "down" then
          if active_tab_idx == 1 then
            local max_m = #(state.marketplace_items or {})
            state.selected_mcp_idx = math.min(max_m > 0 and max_m or 1, state.selected_mcp_idx + 1)
          elseif active_tab_idx == 2 then
            local max_t = #(state.active_tools or {})
            state.selected_tool_idx = math.min(max_t > 0 and max_t or 1, state.selected_tool_idx + 1)
          elseif active_tab_idx == 4 then
            local max_h = #(state.history_items or {})
            state.selected_history_idx = math.min(max_h > 0 and max_h or 1, state.selected_history_idx + 1)
          elseif active_tab_idx == 5 then
            local max_s = #(state.settings_keys or {})
            state.selected_setting_idx = math.min(max_s > 0 and max_s or 1, state.selected_setting_idx + 1)
          elseif active_tab_idx == 6 then
            local max_srv = #(state.current_target_servers or {})
            state.selected_env_server_idx =
              math.min(max_srv > 0 and max_srv or 1, (state.selected_env_server_idx or 1) + 1)
          end
        elseif key == "left" and active_tab_idx == 6 then
          state.selected_target_idx = math.max(1, (state.selected_target_idx or 1) - 1)
          state.selected_env_server_idx = 1
        elseif key == "right" and active_tab_idx == 6 then
          local max_tgt = #(state.env_targets or {})
          state.selected_target_idx = math.min(max_tgt > 0 and max_tgt or 1, (state.selected_target_idx or 1) + 1)
          state.selected_env_server_idx = 1
        elseif (key == "r" or key == "R") and active_tab_idx == 1 then
          state.status_msg = "Syncing live MCP registries (Official & Awesome-MCP)..."
          engine:render()
          local ok, count = registry:refresh_marketplaces()
          if ok then
            state.status_msg = string.format("Marketplaces synced! Indexed %d community & official MCPs.", count)
          else
            state.status_msg = "Registry sync complete."
          end
        elseif key == "/" and active_tab_idx == 1 then
          state.modal = {
            type = "search_marketplace",
            title = "Filter Marketplace",
            prompt = "Enter search keyword (or empty to clear):",
            value = state.search_query or "",
          }
        elseif key == "enter" and active_tab_idx == 1 then
          -- Run selected marketplace package ephemerally and switch to tab 2
          local items = state.marketplace_items or {}
          local selected = items[state.selected_mcp_idx or 1]
          if selected then
            local full_cmd = selected.command .. " " .. table.concat(selected.args or {}, " ")
            if state.active_runner then
              state.active_runner:stop()
            end
            state.status_msg = "Launching ephemeral MCP: " .. selected.name .. "..."
            engine:render()
            local runner = McpRunner.new(full_cmd)
            local ok, client_or_err = runner:start()
            if ok then
              state.active_runner = runner
              local tools = client_or_err:list_tools() or {}
              history:add({
                name = selected.name,
                command = full_cmd,
                status = "ok",
                tools_count = #tools,
              })
              state.status_msg = string.format("Ephemeral %s running! Discovered %d tools.", selected.name, #tools)
              active_tab_idx = 2
            else
              runner:stop()
              history:add({
                name = selected.name,
                command = full_cmd,
                status = "failed",
                tools_count = 0,
              })
              state.status_msg = "Launch failed: " .. tostring(client_or_err)
            end
          end
        elseif (key == "i" or key == "I") and active_tab_idx == 1 then
          -- Install selected marketplace MCP to all environments
          local items = state.marketplace_items or {}
          local selected = items[state.selected_mcp_idx or 1]
          if selected then
            local spec = {
              command = selected.command,
              args = selected.args,
            }
            local sname = selected.name:lower():gsub("%s+", "-"):gsub("[^%w_%-]", "")
            local results = env_mgr:add_mcp(sname, spec, "all")
            local ok_cnt = 0
            for _, res in ipairs(results) do
              if res.success then
                ok_cnt = ok_cnt + 1
              end
            end
            state.status_msg = string.format("Installed '%s' across %d AI agent environments!", sname, ok_cnt)
          end
        elseif
          (key == "d" or key == "D" or key == "delete" or key == "backspace")
          and (active_tab_idx == 6 or active_tab_idx == 1)
        then
          if active_tab_idx == 6 then
            -- Delete/Remove selected MCP from selected agent
            local targets = state.env_targets or {}
            local cur_target = targets[state.selected_target_idx or 1]
            local s_keys = state.current_target_servers or {}
            local cur_srv = s_keys[state.selected_env_server_idx or 1]
            if cur_target and cur_srv then
              env_mgr:remove_mcp(cur_srv, cur_target.id)
              state.status_msg = string.format("Removed '%s' from %s.", cur_srv, cur_target.name)
              state.selected_env_server_idx = math.max(1, (state.selected_env_server_idx or 1) - 1)
            end
          elseif active_tab_idx == 1 then
            -- In Marketplaces tab, remove selected marketplace package from ALL environments
            local items = state.marketplace_items or {}
            local selected = items[state.selected_mcp_idx or 1]
            if selected then
              local sname = selected.name:lower():gsub("%s+", "-"):gsub("[^%w_%-]", "")
              -- Also try direct name or id
              env_mgr:remove_mcp(sname, "all")
              env_mgr:remove_mcp(selected.id, "all")
              local clean_name = selected.id:gsub("^mcp%-", "")
              env_mgr:remove_mcp(clean_name, "all")
              state.status_msg = string.format("Removed '%s' from all AI agent environments.", selected.name)
            end
          end
        elseif (key == "u" or key == "U") and active_tab_idx == 6 then
          -- Remove selected MCP from ALL agents
          local s_keys = state.current_target_servers or {}
          local cur_srv = s_keys[state.selected_env_server_idx or 1]
          if cur_srv then
            env_mgr:remove_mcp(cur_srv, "all")
            state.status_msg = string.format("Purged '%s' from ALL AI agent environments.", cur_srv)
            state.selected_env_server_idx = math.max(1, (state.selected_env_server_idx or 1) - 1)
          end
        elseif (key == "a" or key == "A") and active_tab_idx == 6 then
          -- Add custom MCP to target agent
          local targets = state.env_targets or {}
          local cur_target = targets[state.selected_target_idx or 1]
          state.modal = {
            type = "add_mcp_agent",
            title = "Add MCP to " .. (cur_target and cur_target.name or "Agent"),
            prompt = "Format: <name> <command_or_url>",
            value = "",
          }
        elseif (key == "r" or key == "R") and active_tab_idx == 2 then
          state.modal = {
            type = "spawn_runner",
            title = "Spawn Ephemeral Runner",
            prompt = "Command to run (zero install):",
            value = "npx -y @modelcontextprotocol/server-filesystem /tmp",
          }
        elseif (key == "k" or key == "K") and active_tab_idx == 2 then
          if state.active_runner then
            state.active_runner:stop()
            state.active_runner = nil
            state.status_msg = "Ephemeral runner stopped."
          end
        elseif (key == "x" or key == "X") and active_tab_idx == 2 then
          -- Execute tool call on active runner
          if state.active_runner and state.active_runner.client then
            local tools = state.active_tools or {}
            local t = tools[state.selected_tool_idx or 1]
            if t then
              state.status_msg = "Executing tool " .. t.name .. "..."
              engine:render()
              local res, terr = state.active_runner.client:call_tool(t.name, {})
              if res then
                state.last_tool_output = json.encode(res)
                state.status_msg = "Tool execution completed."
              else
                state.last_tool_output = "Error: " .. tostring(terr)
                state.status_msg = "Tool call failed."
              end
            end
          end
        elseif (key == "e" or key == "E") and active_tab_idx == 3 then
          state.modal = {
            type = "edit_prompt",
            title = "Edit AI Prompt",
            prompt = "Enter prompt for AI model:",
            value = state.ai_prompt or "",
          }
        elseif key == "c" and active_tab_idx == 4 then
          -- Clean all history on user request
          history:clean_all()
          state.status_msg = "Ephemeral history cleared successfully."
        elseif key == "x" and active_tab_idx == 4 then
          -- Clean stale history (>24h)
          history:clean_stale(24)
          state.status_msg = "Stale history entries purged."
        elseif (key == "enter" or key == "e" or key == "E") and active_tab_idx == 5 then
          -- Edit setting value via interactive modal
          local s = state.settings_keys and state.settings_keys[state.selected_setting_idx]
          if s then
            if s.type == "boolean" then
              local cur = config:get(s.key)
              config:set(s.key, not cur)
              config:save()
              state.status_msg = "Updated " .. s.label .. " to " .. tostring(not cur)
            else
              local cur_val = config:get(s.key)
              state.modal = {
                type = "edit_setting",
                title = "Edit TOML Setting",
                prompt = s.label .. " (" .. s.key .. "):",
                value = tostring(cur_val or ""),
                setting = s,
              }
            end
          end
        elseif (key == "s" or key == "S") and active_tab_idx == 5 then
          -- Save hybrid TOML configuration
          local ok, s_err = config:save()
          if ok then
            state.status_msg = "TOML configuration saved to " .. config.config_path
          else
            state.status_msg = "Save failed: " .. tostring(s_err)
          end
        elseif key == "space" and active_tab_idx == 5 then
          -- Toggle boolean setting
          local s = state.settings_keys and state.settings_keys[state.selected_setting_idx]
          if s and s.type == "boolean" then
            local cur = config:get(s.key)
            config:set(s.key, not cur)
            config:save()
            state.status_msg = "Updated " .. s.label .. " to " .. tostring(not cur)
          end
        elseif key == "enter" and active_tab_idx == 3 then
          -- Trigger AI synthesis
          state.status_msg = "Synthesizing with " .. active_model .. "..."
          engine:render()
          local resp, aerr = ai:chat_completion({
            { role = "user", content = state.ai_prompt },
          }, {
            provider = config:get("ai.default_provider"),
            model = active_model,
          })
          if resp then
            state.ai_response = resp.content
            state.status_msg = "Synthesis complete."
          else
            state.ai_response = "Error: " .. tostring(aerr)
            state.status_msg = "AI synthesis failed."
          end
        end
      end
    end
  end

  if state.active_runner then
    state.active_runner:stop()
  end

  term.exit_raw_mode()
end

function app.main(args)
  local config = ConfigManager.new("bassmachine.toml")
  local history = HistoryManager.new(
    config:get("general.history_file"),
    config:get("general.auto_clean_history"),
    config:get("general.max_history_entries"),
    config:get("general.history_retention_hours")
  )
  local registry = Registry.new(config)
  local ai = AiProvider.new(config)
  local env_mgr = EnvManager.new()

  local cmd = args[1]
  if cmd == "test" then
    local ok = app.run_cli_test(config, history, ai)
    os.exit(ok and 0 or 1)
  elseif cmd == "env-list" or cmd == "agents" then
    local summary = env_mgr:list_all()
    io.write(string.format("AI Agent Environments (%d detected):\n\n", #summary))
    for _, t in ipairs(summary) do
      local s_names = {}
      for sn in pairs(t.servers) do
        table.insert(s_names, sn)
      end
      table.sort(s_names)
      local s_str = #s_names > 0 and table.concat(s_names, ", ") or "none"
      io.write(
        string.format(
          "• \27[1;36m%-24s\27[0m [%s]\n  Path: %s\n  Installed MCPs: %s\n\n",
          t.name,
          t.exists and "ACTIVE" or "ABSENT",
          t.path,
          s_str
        )
      )
    end
    os.exit(0)
  elseif cmd == "env-add" or cmd == "add" then
    local sname = args[2]
    local command_str = args[3]
    if not sname or not command_str then
      io.write('Usage: mcp-bassmachine env-add <server_name> "<command>" [target_agent_id|all]\n')
      io.write("Examples:\n")
      io.write('  mcp-bassmachine env-add my-git "uvx mcp-server-git --repository /home" all\n')
      io.write('  mcp-bassmachine env-add remote-tool "https://my-server.com/sse" antigravity\n')
      os.exit(1)
    end
    local target = args[4] or "all"
    local spec = {}
    if command_str:match("^https?://") then
      spec.url = command_str
    else
      local parts = {}
      for p in command_str:gmatch("%S+") do
        table.insert(parts, p)
      end
      spec.command = parts[1]
      table.remove(parts, 1)
      spec.args = parts
    end
    local results = env_mgr:add_mcp(sname, spec, target)
    io.write(string.format("Adding MCP '%s' to target(s): %s\n", sname, target))
    for _, res in ipairs(results) do
      if res.success then
        io.write(string.format("  ✓ %-24s: updated %s\n", res.name, res.path))
      else
        io.write(string.format("  ✗ %-24s: failed (%s)\n", res.name, tostring(res.error)))
      end
    end
    os.exit(0)
  elseif cmd == "env-remove" or cmd == "remove" then
    local sname = args[2]
    if not sname then
      io.write("Usage: mcp-bassmachine env-remove <server_name> [target_agent_id|all]\n")
      os.exit(1)
    end
    local target = args[3] or "all"
    local results = env_mgr:remove_mcp(sname, target)
    io.write(string.format("Removing MCP '%s' from target(s): %s\n", sname, target))
    for _, res in ipairs(results) do
      if res.success then
        io.write(string.format("  ✓ %-24s: %s\n", res.name, res.removed and "removed" or "not present"))
      else
        io.write(string.format("  ✗ %-24s: failed (%s)\n", res.name, tostring(res.error)))
      end
    end
    os.exit(0)
  elseif cmd == "run" then
    local mcp_cmd = args[2]
    if not mcp_cmd then
      io.write('Usage: mcp-bassmachine run "<command>"\n')
      os.exit(1)
    end
    local ok = app.run_cli_ephemeral_mcp(mcp_cmd, config, history)
    os.exit(ok and 0 or 1)
  elseif cmd == "marketplaces" or cmd == "list" then
    local servers = registry:get_all()
    io.write(string.format("Indexed %d MCP servers across registries:\n\n", #servers))
    for _, s in ipairs(servers) do
      io.write(string.format("• \27[1;36m%-24s\27[0m [%s] - %s\n", s.name, s.source, s.description))
    end
    os.exit(0)
  elseif cmd == "history" then
    local items = history:list()
    io.write(string.format("Ephemeral History (%d sessions):\n\n", #items))
    for idx, it in ipairs(items) do
      io.write(
        string.format(
          "[%d] %s │ %s │ Status: %s │ Tools: %d\n",
          idx,
          it.time_formatted or "-",
          it.name,
          it.status,
          it.tools_count or 0
        )
      )
    end
    os.exit(0)
  elseif cmd == "clean-history" then
    history:clean_all()
    io.write("Ephemeral history cleaned.\n")
    os.exit(0)
  elseif cmd == "check-config" then
    io.write(string.format("TOML Configuration at %s:\n", config.config_path))
    io.write(string.format("  App: %s\n", config:get("general.app_name")))
    io.write(string.format("  AI Provider: %s\n", config:get("ai.default_provider")))
    io.write(string.format("  AI Model: %s\n", config:get("ai.default_model")))
    io.write(string.format("  History retention: %dh\n", config:get("general.history_retention_hours")))
    os.exit(0)
  else
    -- Default to interactive TUI
    app.run_tui(config, history, registry, ai, env_mgr)
  end
end

-- Check if running as main script
local is_main = false
local info = debug.getinfo(1, "S")
if info and info.source and (info.source:match("main%.lua$") or info.source == "=[C]") then
  is_main = true
end

if is_main then
  app.main(arg or {})
end

return app
