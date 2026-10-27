rockspec_format = "3.0"
package = "ai-bassmachine"
version = "0.1.0-1"

source = {
  url = "git+https://github.com/nationdex/ai-bassmachine.git",
  tag = "v0.1.0",
}

description = {
  summary = "A powerful, clean Lua TUI to test, configure and run MCP servers & Agent Skills with multi-AI backend support",
  detailed = [[
    AI Bass Machine is an ultra-fast, zero-install TUI and CLI suite to discover,
    inspect, configure, and sync Model Context Protocol (MCP) servers and Agent Skills
    across AI agent environments. Features dynamic TOML configuration, on-demand ephemeral runners,
    and native multi-provider AI synthesis.
  ]],
  homepage = "https://github.com/nationdex/ai-bassmachine",
  license = "Apache-2.0",
  maintainer = "NDS <arielaram@nationdex.com>",
}

dependencies = {
  "lua >= 5.1",
}

build = {
  type = "builtin",
  modules = {
    ["ai-bassmachine.main"] = "src/main.lua",
    ["ai-bassmachine.config.toml"] = "src/config/toml.lua",
    ["ai-bassmachine.config.manager"] = "src/config/manager.lua",
    ["ai-bassmachine.mcp.client"] = "src/mcp/client.lua",
    ["ai-bassmachine.mcp.runner"] = "src/mcp/runner.lua",
    ["ai-bassmachine.mcp.history"] = "src/mcp/history.lua",
    ["ai-bassmachine.marketplace.registry"] = "src/marketplace/registry.lua",
    ["ai-bassmachine.env.manager"] = "src/env/manager.lua",
    ["ai-bassmachine.skills.manager"] = "src/skills/manager.lua",
    ["ai-bassmachine.ai.provider"] = "src/ai/provider.lua",
    ["ai-bassmachine.ui.engine"] = "src/ui/engine.lua",
    ["ai-bassmachine.ui.widgets"] = "src/ui/widgets.lua",
    ["ai-bassmachine.ui.views"] = "src/ui/views.lua",
    ["ai-bassmachine.utils.json"] = "src/utils/json.lua",
    ["ai-bassmachine.utils.term"] = "src/utils/term.lua",
    -- Backward compatibility aliases
    ["mcp-bassmachine.main"] = "src/main.lua",
    ["mcp-bassmachine.config.toml"] = "src/config/toml.lua",
    ["mcp-bassmachine.config.manager"] = "src/config/manager.lua",
    ["mcp-bassmachine.mcp.client"] = "src/mcp/client.lua",
    ["mcp-bassmachine.mcp.runner"] = "src/mcp/runner.lua",
    ["mcp-bassmachine.mcp.history"] = "src/mcp/history.lua",
    ["mcp-bassmachine.marketplace.registry"] = "src/marketplace/registry.lua",
    ["mcp-bassmachine.env.manager"] = "src/env/manager.lua",
    ["mcp-bassmachine.skills.manager"] = "src/skills/manager.lua",
    ["mcp-bassmachine.ai.provider"] = "src/ai/provider.lua",
    ["mcp-bassmachine.ui.engine"] = "src/ui/engine.lua",
    ["mcp-bassmachine.ui.widgets"] = "src/ui/widgets.lua",
    ["mcp-bassmachine.ui.views"] = "src/ui/views.lua",
    ["mcp-bassmachine.utils.json"] = "src/utils/json.lua",
    ["mcp-bassmachine.utils.term"] = "src/utils/term.lua",
  },
  install = {
    bin = {
      ["ai-bassmachine"] = "bin/ai-bassmachine",
      ["mcp-bassmachine"] = "bin/mcp-bassmachine",
    },
  },
}
