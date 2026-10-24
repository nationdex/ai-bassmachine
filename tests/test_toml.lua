package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local toml = require("mcp-bassmachine.config.toml")

local sample = [[
# Main configuration
title = "MCP Bass Machine"
enabled = true
port = 8080
ratio = 3.14

[server]
host = "127.0.0.1"
tags = ["fast", "neon", "mcp"]

[server.database]
engine = "sqlite"
timeout = 30
]]

local parsed = toml.parse(sample)

assert(parsed.title == "MCP Bass Machine", "title mismatch")
assert(parsed.enabled == true, "enabled mismatch")
assert(parsed.port == 8080, "port mismatch")
assert(parsed.ratio == 3.14, "ratio mismatch")
assert(parsed.server.host == "127.0.0.1", "server.host mismatch")
assert(#parsed.server.tags == 3, "tags length mismatch")
assert(parsed.server.tags[1] == "fast", "tags[1] mismatch")
assert(parsed.server.database.engine == "sqlite", "server.database.engine mismatch")
assert(parsed.server.database.timeout == 30, "server.database.timeout mismatch")

-- Test encode
local encoded = toml.encode(parsed)
local roundtrip = toml.parse(encoded)

assert(roundtrip.title == parsed.title, "roundtrip title mismatch")
assert(roundtrip.enabled == parsed.enabled, "roundtrip enabled mismatch")
assert(roundtrip.port == parsed.port, "roundtrip port mismatch")
assert(roundtrip.server.database.engine == parsed.server.database.engine, "roundtrip nested mismatch")

io.write("PASS: tests/test_toml.lua\n")
