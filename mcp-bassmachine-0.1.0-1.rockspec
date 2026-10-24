rockspec_format = "3.0"
package = "mcp-bassmachine"
version = "0.1.0-1"

source = {
  url = "git+https://github.com/nationdex/mcp-bassmachine.git",
  tag = "v0.1.0",
}

description = {
  summary = "A powerful, clean Lua TUI to test, inspect and run MCP servers with multi-AI backend support",
  detailed = [[
    MCP Bass Machine is an ultra-fast, zero-install TUI and CLI suite to discover,
    inspect, benchmark, and run Model Context Protocol (MCP) servers across multiple
    marketplaces. Features hybrid live TOML configuration, on-demand ephemeral runners,
    and native AI synthesis with ZenMux, OpenRouter, and more.
  ]],
  homepage = "https://github.com/nationdex/mcp-bassmachine",
  license = "MIT",
  maintainer = "NationDex <arielaram@nationdex.com>",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["mcp-bassmachine.main"] = "src/main.lua",
    ["mcp-bassmachine.config.toml"] = "src/config/toml.lua",
    ["mcp-bassmachine.config.manager"] = "src/config/manager.lua",
    ["mcp-bassmachine.mcp.client"] = "src/mcp/client.lua",
    ["mcp-bassmachine.mcp.runner"] = "src/mcp/runner.lua",
    ["mcp-bassmachine.mcp.history"] = "src/mcp/history.lua",
    ["mcp-bassmachine.marketplace.registry"] = "src/marketplace/registry.lua",
    ["mcp-bassmachine.env.manager"] = "src/env/manager.lua",
    ["mcp-bassmachine.ai.provider"] = "src/ai/provider.lua",
    ["mcp-bassmachine.ui.engine"] = "src/ui/engine.lua",
    ["mcp-bassmachine.ui.widgets"] = "src/ui/widgets.lua",
    ["mcp-bassmachine.ui.views"] = "src/ui/views.lua",
    ["mcp-bassmachine.utils.json"] = "src/utils/json.lua",
    ["mcp-bassmachine.utils.term"] = "src/utils/term.lua",
  },
  install = {
    bin = {
      ["mcp-bassmachine"] = "bin/mcp-bassmachine",
    },
  },
}
