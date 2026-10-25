package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local term = require("mcp-bassmachine.utils.term")
local ConfigManager = require("mcp-bassmachine.config.manager")
local AiProvider = require("mcp-bassmachine.ai.provider")

local KEY = "sk-FAKE-security-key-0987654321"

local function read_all(p)
  local f = io.open(p, "r")
  if not f then
    return nil
  end
  local c = f:read("*a")
  f:close()
  return c
end

local config = ConfigManager.new("/nonexistent/bassmachine.toml")
config:set("providers.zenmux.api_key", KEY)
local ai = AiProvider.new(config)

-- Capture the shell command instead of running it
local captured = {}
local real_popen = term.safe_popen
term.safe_popen = function(cmd)
  local cfg_path = cmd:match("%-K '([^']+)'")
  captured.cmd = cmd
  captured.cfg = cfg_path and read_all(cfg_path)
  return {
    read = function()
      return '{"choices":[{"message":{"content":"ok"}}],"model":"m"}'
    end,
    close = function() end,
  }
end

-- 1. Key must live in the private config file, never in the command line
local resp, err = ai:chat_completion({ { role = "user", content = "hi" } }, { provider = "zenmux" })
assert(resp, "chat_completion failed: " .. tostring(err))
assert(not captured.cmd:find(KEY, 1, true), "API key leaked into command line: " .. captured.cmd)
assert(captured.cfg and captured.cfg:find(KEY, 1, true), "API key missing from curl config")

-- 2. Temp files are cleaned up
local cfg_path = captured.cmd:match("%-K '([^']+)'")
assert(read_all(cfg_path) == nil, "curl config not removed")

-- 3. Injection through model id / base_url is rejected before anything is spawned
captured = {}
local _, e1 = ai:chat_completion(
  { { role = "user", content = "hi" } },
  { provider = "zenmux", model = "x'; touch /tmp/pwned; '" }
)
assert(e1 and e1:find("Invalid model id"), "malicious model id accepted: " .. tostring(e1))
assert(captured.cmd == nil, "curl spawned for invalid model")

config:set("providers.zenmux.base_url", "https://evil.test/'; touch /tmp/pwned; '")
local _, e2 = ai:chat_completion({ { role = "user", content = "hi" } }, { provider = "zenmux" })
assert(e2 and e2:find("Invalid base_url"), "malicious base_url accepted: " .. tostring(e2))
assert(captured.cmd == nil, "curl spawned for invalid base_url")
config:set("providers.zenmux.base_url", "https://zenmux.ai/api/v1")

-- 4. Gemini key goes in a header, not the URL
config:set("providers.gemini.api_key", KEY)
captured = {}
ai:chat_completion({ { role = "user", content = "hi" } }, { provider = "gemini", model = "gemini-2.0-flash" })
assert(captured.cfg and not captured.cfg:find("key=", 1, true), "Gemini key still in URL query")
assert(captured.cfg:find("x-goog-api-key", 1, true), "Gemini key header missing")

-- 5. Parse-failure errors never echo the key
term.safe_popen = function()
  return {
    read = function()
      return "not json " .. KEY
    end,
    close = function() end,
  }
end
local _, e3 = ai:chat_completion({ { role = "user", content = "hi" } }, { provider = "zenmux" })
assert(e3 and not e3:find(KEY, 1, true), "API key echoed in error: " .. tostring(e3))

-- 6. Tools are actually forwarded (format_tools used to receive `self`)
local seen_body
term.safe_popen = function(cmd)
  local cfg = read_all(cmd:match("%-K '([^']+)'"))
  local body_path = cfg and cfg:match('data%-binary = "@([^"]+)"')
  seen_body = body_path and read_all(body_path)
  return {
    read = function()
      return '{"choices":[{"message":{"content":"ok"}}]}'
    end,
    close = function() end,
  }
end
ai:chat_completion(
  { { role = "user", content = "hi" } },
  { provider = "zenmux", tools = { { name = "t1", description = "d", inputSchema = { type = "object" } } } }
)
assert(seen_body and seen_body:find('"tools"', 1, true), "tools not sent in request body")

term.safe_popen = real_popen

-- 7. term helpers
assert(term.shell_quote("a'b") == "'a'\\''b'", "shell_quote mishandles single quote")
assert(term.redact("x " .. KEY .. " y", { KEY }) == "x *** y", "redact failed")
assert(#term.random_hex(8) == 16, "random_hex length")
assert(term.random_hex(8) ~= term.random_hex(8), "random_hex not random")

io.write("PASS: tests/test_ai_security.lua\n")
