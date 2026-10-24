# MCP Bass Machine

An ultra-fast, zero-dependency Lua 5.X ANSI terminal workspace to discover, test, benchmark, and run Model Context Protocol (MCP) servers across multiple marketplaces.

```
 🎛  MCP BASS MACHINE  [ ▂▃▄▅▆▇█]                   AI: deepseek/deepseek-v4.1-flash │ Tab: Marketplaces
──────────────────────────────────────────────────────────────────────────────────────────────────────────
 1:Marketplaces   2:Test & Run   3:AI Synth   4:History   5:Settings
┌ Marketplace Catalog ──────────────────┐┌ Package Specs & Zero-Install Preview ─────────────────────────┐
│ [OFFICIAL]   mcp-filesystem           ││ Package:     Filesystem MCP                                    │
│ [OFFICIAL]   mcp-fetch                ││ Registry:    official                                          │
│ [OFFICIAL]   mcp-sqlite               ││ Maintainer:  Model Context Protocol Official                   │
│ [OFFICIAL]   mcp-git                  ││ Category:    Utilities                                         │
│ [SMITHERY]   mcp-brave-search         ││                                                                │
│ [OFFICIAL]   mcp-memory               ││ Ephemeral Run Command (No Global Install):                     │
│ [GLAMA]      mcp-postgres             ││ $ npx -y @modelcontextprotocol/server-filesystem /tmp          │
│ [OFFICIAL]   mcp-everything           ││                                                                │
│ [AWESOME-MCP]mcp-github               ││ Description: Secure direct filesystem access with configurable │
│ [SMITHERY]   mcp-puppeteer            ││ read/write boundaries.                                         │
└───────────────────────────────────────┘└────────────────────────────────────────────────────────────────┘
 [1-5] Tabs │ [↑/↓] Navigate │ [C] Clean │ [S] Save TOML │ [Q] Quit
```

---

## Highlights

- **Pure Lua & Zero C Dependencies**: Runs seamlessly across Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT with zero compilation step.
- **Zero-Install Ephemeral Execution**: MCP servers run on-demand via isolated FIFO coprocesses (`npx -y`, `uvx`, docker). No global npm or python environment pollution.
- **Auto-Cleaning History**: Every execution session is tracked in an ephemeral history ledger with execution duration, tool count, and status. Automatically purges old records or cleans on-demand.
- **Multi-Marketplace Hub**: Real-time discovery aggregating servers from official Model Context Protocol registries, Smithery.ai, Glama, and Awesome-MCP.
- **Hybrid TOML Engine**: Pure Lua TOML parser and serializer. Edit configurations directly in the TUI with live file sync and environment variable interpolation (`${ENV_VAR}`).
- **Native Multi-AI Synthesis**: Direct tool-calling integration with ZenMux, OpenRouter, DeepSeek, and local LLM endpoints (Ollama/vLLM). The AI receives MCP tool schemas and executes live tool invocations.
- **Strict Quality Pipeline**: Stylua formatting, Luacheck linting, and Teal (`tl`) typechecked definitions.

---

## Installation & Quick Start

### Prerequisites
- Lua 5.1+ or LuaJIT
- `curl` and POSIX shell (`stty`, `mkfifo`)

### Running the TUI
```bash
git clone https://github.com/nationdex/mcp-bassmachine.git
cd mcp-bassmachine

# Launch interactive TUI
./bin/mcp-bassmachine
```

### CLI Mode
```bash
# Run preflight verification test (verifies TOML, history, marketplaces, and ZenMux AI)
./bin/mcp-bassmachine test

# Run an MCP server ephemerally and introspect tools
./bin/mcp-bassmachine run "npx -y @modelcontextprotocol/server-filesystem /tmp"

# List indexed MCPs across marketplaces
./bin/mcp-bassmachine list

# Inspect ephemeral run history
./bin/mcp-bassmachine history

# Clear session history
./bin/mcp-bassmachine clean-history

# Check active TOML configuration
./bin/mcp-bassmachine check-config
```

---

## Configuration (`bassmachine.toml`)

Configurations use TOML and support live in-TUI modification:

```toml
[general]
app_name = "MCP Bass Machine"
auto_clean_history = true
max_history_entries = 50
history_retention_hours = 24

[ui]
theme = "neon-bass"
frame_rate = 30
bass_meter = true

[ai]
default_provider = "zenmux"
default_model = "deepseek/deepseek-v4.1-flash"
temperature = 0.7
max_tokens = 4096

[providers.zenmux]
name = "ZenMux AI"
base_url = "https://zenmux.ai/api/v1"
api_key = "${ZENMUX_API_KEY}"
default_model = "deepseek/deepseek-v4.1-flash"

[providers.openrouter]
name = "OpenRouter"
base_url = "https://openrouter.ai/api/v1"
api_key = "${OPENROUTER_API_KEY}"
default_model = "anthropic/claude-3.5-sonnet"
```

---

## TUI Keyboard Navigation

| Key | Action |
|---|---|
| `1` - `5` | Switch active tab (Marketplaces, Test & Run, AI Synth, History, Settings) |
| `Tab` | Cycle next tab |
| `↑` / `↓` | Navigate list items and menu options |
| `Enter` | Launch ephemeral run (Tab 1), Trigger AI synthesis (Tab 3) |
| `Space` | Toggle boolean values in Settings (Tab 5) |
| `C` | Clean all ephemeral session history (Tab 4) |
| `X` | Clean stale sessions older than retention limit (Tab 4) |
| `S` | Write and synchronize modified settings to `bassmachine.toml` (Tab 5) |
| `Q` / `Ctrl+C` | Gracefully quit and restore terminal state |

---

## Development & Verification

### Formatter
```bash
stylua src tests
```

### Linter
```bash
luacheck src tests
```

### Typechecker
```bash
tl check types/mcp_bassmachine.d.tl
```

### Test Suite
```bash
lua tests/test_json.lua
lua tests/test_toml.lua
lua tests/test_history.lua
lua tests/test_mcp_protocol.lua
lua tests/test_ai_zenmux.lua
```

---

## Architecture

```
mcp-bassmachine/
├── bin/
│   └── mcp-bassmachine             # Executable launcher
├── src/
│   ├── main.lua                    # TUI & CLI entrypoint
│   ├── loader.lua                  # Cross-version module searcher
│   ├── config/
│   │   ├── toml.lua                # Pure Lua TOML parser & encoder
│   │   └── manager.lua             # Hybrid runtime configuration manager
│   ├── mcp/
│   │   ├── client.lua              # JSON-RPC 2.0 MCP client
│   │   ├── runner.lua              # Ephemeral FIFO coprocess runner
│   │   └── history.lua             # Session tracker with auto-cleanup
│   ├── marketplace/
│   │   └── registry.lua            # Multi-registry aggregator & search
│   ├── ai/
│   │   └── provider.lua            # Multi-AI synthesis (ZenMux, OpenRouter)
│   ├── ui/
│   │   ├── engine.lua              # ANSI terminal engine & bass visualizer
│   │   ├── widgets.lua             # Reusable UI component library
│   │   └── views.lua               # Views (Marketplaces, Test, AI, History, TOML)
│   └── utils/
│       ├── json.lua                # Pure Lua JSON parser/encoder
│       └── term.lua                # ANSI sequences, raw mode, keyboard events
├── types/
│   └── mcp_bassmachine.d.tl        # Teal type definitions
├── tests/
│   ├── test_json.lua
│   ├── test_toml.lua
│   ├── test_history.lua
│   ├── test_mcp_protocol.lua
│   └── test_ai_zenmux.lua
├── .github/workflows/
│   ├── ci.yml                      # CI test matrix across Lua 5.1-5.4 & LuaJIT
│   └── release.yml                 # Automated release packaging
├── bassmachine.toml                # Active TOML configuration
├── stylua.toml                     # Stylua rules
├── .luacheckrc                     # Luacheck linter configuration
├── tlconfig.json                   # Teal typechecker configuration
└── mcp-bassmachine-0.1.0-1.rockspec # LuaRocks package definition
```

---

## License

MIT © NationDex
