package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local McpRunner = require("ai-bassmachine.mcp.runner")

-- A program that cannot exist must fail fast with a hint, without spawning anything
local runner = McpRunner.new("npx-definitely-not-installed-xyz -y pkg")
local ok, err = runner:start()
assert(not ok, "start must fail for a missing program")
-- Windows: where.exe gives the early hint; where it is unavailable (wine) the spawn fails readably instead
assert(
  tostring(err):find("not found on PATH", 1, true) or tostring(err):find("Handshake failed", 1, true),
  "unexpected error: " .. tostring(err)
)
assert(not tostring(err):find("\n"), "error must be a single line")

-- Known tool gets an install hint
local missing = McpRunner.new("npx")
if not McpRunner.program_exists("npx") then
  local _, e2 = missing:start()
  assert(e2:find("Node.js", 1, true), "npx hint missing: " .. tostring(e2))
end

-- POSIX only: `where` is not reliably available under wine, real Windows is covered by CI
if package.config:sub(1, 1) == "/" then
  assert(McpRunner.program_exists("sh"), "program_exists broken")
end

io.write("PASS: tests/test_runner_preflight.lua\n")
