-- MCP Bass Machine - Multi-AI Provider & Tool Synthesis Engine
-- Bridges MCP tools with ZenMux, Anthropic, Gemini, OpenAI, OpenRouter, DeepSeek, and Ollama.

local json = require("mcp-bassmachine.utils.json")
local term = require("mcp-bassmachine.utils.term")

local AiProvider = {}
AiProvider.__index = AiProvider

-- Default fallback models per provider when dynamic fetching is offline or unauthenticated
AiProvider.DEFAULT_MODELS = {
  zenmux = {
    "deepseek/deepseek-v4.1-flash",
    "deepseek/deepseek-chat",
    "deepseek/deepseek-reasoner",
    "anthropic/claude-3.5-sonnet",
    "openai/gpt-4o",
    "openai/gpt-4o-mini",
    "google/gemini-2.0-flash",
  },
  openrouter = {
    "anthropic/claude-3.5-sonnet",
    "anthropic/claude-3.5-haiku",
    "openai/gpt-4o",
    "openai/gpt-4o-mini",
    "google/gemini-2.0-flash",
    "meta-llama/llama-3.3-70b-instruct",
    "deepseek/deepseek-chat",
  },
  openai = {
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "o1",
    "o1-mini",
    "o3-mini",
  },
  anthropic = {
    "claude-3-5-sonnet-20241022",
    "claude-3-5-haiku-20241022",
    "claude-3-opus-20240229",
  },
  gemini = {
    "gemini-2.0-flash",
    "gemini-1.5-pro",
    "gemini-1.5-flash",
  },
  deepseek = {
    "deepseek-chat",
    "deepseek-reasoner",
  },
  ollama = {
    "llama3:latest",
    "mistral:latest",
    "qwen2.5-coder:latest",
    "phi3:latest",
    "deepseek-r1:latest",
  },
}

-- Dynamically list models available from an AI service
function AiProvider:fetch_available_models(provider_name)
  provider_name = provider_name or self.config:get("ai.default_provider", "zenmux")
  local prov, prov_id = self:get_active_provider_config(provider_name)
  local api_key = prov.api_key or ""
  local base_url = prov.base_url or "https://zenmux.ai/api/v1"

  local models = {}

  -- 1. Try dynamic /models endpoint
  local endpoint = nil
  local headers = "-H 'Content-Type: application/json'"
  if prov_id == "gemini" then
    if #api_key > 0 then
      endpoint = string.format("%s/models?key=%s", base_url, api_key)
    end
  elseif prov_id == "anthropic" then
    if #api_key > 0 then
      endpoint = base_url .. "/models"
      headers = string.format("-H 'x-api-key: %s' -H 'anthropic-version: 2023-06-01'", api_key)
    end
  elseif prov_id == "ollama" then
    endpoint = base_url:gsub("/v1/?$", "") .. "/api/tags"
  else
    -- OpenAI, ZenMux, OpenRouter, DeepSeek (standard /models)
    if #api_key > 0 or prov_id == "openrouter" then
      endpoint = base_url .. "/models"
      if #api_key > 0 then
        headers = headers .. string.format(" -H 'Authorization: Bearer %s'", api_key)
      end
    end
  end

  if endpoint then
    local curl_cmd = string.format("curl -s -m 5 %s '%s' 2>/dev/null", headers, endpoint)
    local pipe = term.safe_popen(curl_cmd)
    if pipe then
      local resp = pipe:read("*a")
      pipe:close()
      if resp and #resp > 0 then
        local decoded = json.decode(resp)
        if decoded and type(decoded) == "table" then
          -- OpenAI / ZenMux / OpenRouter format: { data: [ { id: "..." } ] }
          if decoded.data and type(decoded.data) == "table" then
            for _, m in ipairs(decoded.data) do
              if m.id then
                table.insert(models, m.id)
              end
            end
          -- Gemini format: { models: [ { name: "models/gemini-..." } ] }
          elseif decoded.models and type(decoded.models) == "table" then
            for _, m in ipairs(decoded.models) do
              local mname = m.name and m.name:gsub("^models/", "") or m.name
              if mname then
                table.insert(models, mname)
              end
            end
          -- Ollama format: { models: [ { name: "..." } ] }
          elseif decoded.models and type(decoded.models) == "table" then
            for _, m in ipairs(decoded.models) do
              if m.name then
                table.insert(models, m.name)
              end
            end
          end
        end
      end
    end
  end

  -- 2. Fall back to curated defaults if dynamic API query returned none
  if #models == 0 then
    local defaults = self.DEFAULT_MODELS[prov_id] or self.DEFAULT_MODELS.zenmux
    for _, m in ipairs(defaults) do
      table.insert(models, m)
    end
  end

  table.sort(models)
  return models
end

function AiProvider.new(config)
  local self = setmetatable({}, AiProvider)
  self.config = config
  return self
end

function AiProvider:get_active_provider_config(provider_name)
  provider_name = provider_name or self.config:get("ai.default_provider", "zenmux")
  local prov = self.config:get("providers." .. provider_name)
  if not prov then
    prov = {
      name = "ZenMux AI",
      base_url = "https://zenmux.ai/api/v1",
      api_key = self.config:get("providers.zenmux.api_key", ""),
      default_model = self.config:get("ai.default_model", "deepseek/deepseek-v4.1-flash"),
    }
  end
  return prov, provider_name
end

-- Convert MCP tools into OpenAI/ZenMux function calling format
function AiProvider.format_tools(mcp_tools)
  if not mcp_tools or #mcp_tools == 0 then
    return nil
  end
  local formatted = {}
  for _, tool in ipairs(mcp_tools) do
    table.insert(formatted, {
      type = "function",
      ["function"] = {
        name = tool.name,
        description = tool.description or ("Tool: " .. tool.name),
        parameters = tool.inputSchema or { type = "object", properties = {} },
      },
    })
  end
  return formatted
end

function AiProvider:chat_completion(messages, options)
  options = options or {}
  local prov, prov_id = self:get_active_provider_config(options.provider)
  local api_key = options.api_key or prov.api_key
  local model = options.model or prov.default_model or "deepseek/deepseek-v4.1-flash"
  local base_url = prov.base_url or "https://zenmux.ai/api/v1"

  if not api_key or #api_key == 0 then
    return nil, "Missing API key for provider '" .. tostring(prov_id) .. "'"
  end

  local endpoint = base_url .. "/chat/completions"
  local payload = {
    model = model,
    messages = messages,
    temperature = options.temperature or self.config:get("ai.temperature", 0.7),
    max_tokens = options.max_tokens or self.config:get("ai.max_tokens", 2048),
  }

  if options.tools and #options.tools > 0 then
    payload.tools = self:format_tools(options.tools)
  end

  local json_payload = json.encode(payload)

  -- Write payload to temporary file to avoid shell escaping issues
  local tmp_dir = term.get_temp_dir()
  local tmp_payload = string.format("%s/mcp_bass_ai_req_%d_%d.json", tmp_dir, os.time(), math.random(1000, 9999))
  local pf = io.open(tmp_payload, "w")
  if not pf then
    return nil, "Could not write temporary request payload"
  end
  pf:write(json_payload)
  pf:close()

  local timeout = options.timeout or self.config:get("ai.request_timeout_seconds", 60)
  local curl_cmd

  if prov_id == "anthropic" then
    endpoint = base_url .. "/messages"
    local system_prompt = nil
    local user_messages = {}
    for _, msg in ipairs(messages) do
      if msg.role == "system" then
        system_prompt = msg.content
      else
        table.insert(user_messages, msg)
      end
    end
    local ant_payload = {
      model = model,
      messages = user_messages,
      max_tokens = options.max_tokens or self.config:get("ai.max_tokens", 2048),
      temperature = options.temperature or self.config:get("ai.temperature", 0.7),
    }
    if system_prompt then
      ant_payload.system = system_prompt
    end
    local ant_pf = io.open(tmp_payload, "w")
    if ant_pf then
      ant_pf:write(json.encode(ant_payload))
      ant_pf:close()
    end
    curl_cmd = string.format(
      "curl -s -m %d -X POST '%s' "
        .. "-H 'x-api-key: %s' "
        .. "-H 'anthropic-version: 2023-06-01' "
        .. "-H 'Content-Type: application/json' "
        .. "--data-binary '@%s' 2>/dev/null",
      timeout,
      endpoint,
      api_key,
      tmp_payload
    )
  elseif prov_id == "gemini" then
    endpoint = string.format("%s/models/%s:generateContent?key=%s", base_url, model, api_key)
    local contents = {}
    for _, msg in ipairs(messages) do
      local role = (msg.role == "assistant") and "model" or "user"
      table.insert(contents, {
        role = role,
        parts = { { text = msg.content } },
      })
    end
    local gem_payload = { contents = contents }
    local gem_pf = io.open(tmp_payload, "w")
    if gem_pf then
      gem_pf:write(json.encode(gem_payload))
      gem_pf:close()
    end
    curl_cmd = string.format(
      "curl -s -m %d -X POST '%s' " .. "-H 'Content-Type: application/json' " .. "--data-binary '@%s' 2>/dev/null",
      timeout,
      endpoint,
      tmp_payload
    )
  else
    curl_cmd = string.format(
      "curl -s -m %d -X POST '%s' "
        .. "-H 'Authorization: Bearer %s' "
        .. "-H 'Content-Type: application/json' "
        .. "-H 'HTTP-Referer: https://github.com/nationdex/mcp-bassmachine' "
        .. "-H 'X-Title: MCP Bass Machine' "
        .. "--data-binary '@%s' 2>/dev/null",
      timeout,
      endpoint,
      api_key,
      tmp_payload
    )
  end

  local pipe = term.safe_popen(curl_cmd)
  if not pipe then
    os.remove(tmp_payload)
    return nil, "Failed to spawn curl process"
  end

  local resp_body = pipe:read("*a")
  pipe:close()
  os.remove(tmp_payload)

  if not resp_body or #resp_body == 0 then
    return nil, "Empty response from AI endpoint"
  end

  local decoded, parse_err = json.decode(resp_body)
  if not decoded then
    return nil, "Failed to parse AI JSON response: " .. tostring(parse_err) .. " (Raw: " .. resp_body .. ")"
  end

  if decoded.error then
    local err_msg = type(decoded.error) == "table" and (decoded.error.message or decoded.error.code)
      or tostring(decoded.error)
    return nil, "AI API Error: " .. tostring(err_msg)
  end

  -- Handle Anthropic native response format: { content: [ { type: "text", text: "..." } ] }
  if prov_id == "anthropic" then
    local content = ""
    if decoded.content and type(decoded.content) == "table" then
      for _, part in ipairs(decoded.content) do
        if part.type == "text" and part.text then
          content = content .. part.text
        end
      end
    end
    return {
      content = content,
      reasoning = nil,
      tool_calls = nil,
      model = decoded.model or model,
      usage = decoded.usage or {},
      raw = decoded,
    }
  end

  -- Handle Gemini native response format: { candidates: [ { content: { parts: [ { text: "..." } ] } } ] }
  if prov_id == "gemini" then
    local content = ""
    local cand = decoded.candidates and decoded.candidates[1]
    if cand and cand.content and cand.content.parts then
      for _, part in ipairs(cand.content.parts) do
        if part.text then
          content = content .. part.text
        end
      end
    end
    return {
      content = content,
      reasoning = nil,
      tool_calls = nil,
      model = model,
      usage = decoded.usageMetadata or {},
      raw = decoded,
    }
  end

  local choice = decoded.choices and decoded.choices[1]
  if not choice or not choice.message then
    return nil, "Invalid response schema from AI provider"
  end

  return {
    content = choice.message.content or "",
    reasoning = choice.message.reasoning or nil,
    tool_calls = choice.message.tool_calls or nil,
    model = decoded.model or model,
    usage = decoded.usage or {},
    raw = decoded,
  }
end

-- Synthesize: Runs prompt with AI, executes tool calls against MCP client if requested, and produces final result
function AiProvider:synthesize_with_mcp(prompt, mcp_client, options)
  options = options or {}
  local tools = {}
  if mcp_client and mcp_client.list_tools then
    local tl = mcp_client:list_tools()
    if tl then
      tools = tl
    end
  end

  local messages = {
    {
      role = "system",
      content = "You are MCP Bass Machine, an ultra-fast agent powered by Model Context Protocol tools.",
    },
    {
      role = "user",
      content = prompt,
    },
  }

  local resp, err = self:chat_completion(messages, {
    provider = options.provider,
    model = options.model,
    api_key = options.api_key,
    tools = tools,
  })

  if not resp then
    return nil, err
  end

  -- If model decided to invoke an MCP tool
  if resp.tool_calls and #resp.tool_calls > 0 and mcp_client then
    local executed_tools = {}
    for _, call in ipairs(resp.tool_calls) do
      local fn = call["function"]
      local fn_name = fn and fn.name
      local args_str = fn and fn.arguments
      local args = {}
      if args_str and type(args_str) == "string" then
        args = json.decode(args_str) or {}
      elseif type(args_str) == "table" then
        args = args_str
      end

      local tool_res, tool_err = mcp_client:call_tool(fn_name, args)
      table.insert(executed_tools, {
        id = call.id,
        name = fn_name,
        arguments = args,
        result = tool_res,
        error = tool_err,
      })

      -- Append assistant tool call and tool response message
      table.insert(messages, {
        role = "assistant",
        content = resp.content or "",
        tool_calls = { call },
      })
      table.insert(messages, {
        role = "tool",
        tool_call_id = call.id,
        content = json.encode(tool_res or { error = tool_err }),
      })
    end

    -- Run follow-up completion for final synthesis
    local follow_up, _ = self:chat_completion(messages, {
      provider = options.provider,
      model = options.model,
      api_key = options.api_key,
    })

    if follow_up then
      follow_up.executed_tools = executed_tools
      return follow_up
    end
  end

  return resp
end

return AiProvider
