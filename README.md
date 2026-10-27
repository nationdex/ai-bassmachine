# AI Bass Machine

An ultra-fast, zero-dependency Lua 5.X ANSI terminal workspace to discover, configure, test, benchmark, and sync Model Context Protocol (MCP) servers and Agent Skills across all AI agent environments.

```
 🎛  AI BASS MACHINE  [ ▂▃▄▅▆▇█]                   AI: deepseek/deepseek-v4.1-flash │ Tab: Marketplaces
──────────────────────────────────────────────────────────────────────────────────────────────────────────
 1:Marketplaces   2:Test & Run   3:Skills   4:AI Synth   5:History   6:Settings   7:Agent Sync
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
 [1-7] Tabs │ [↑/↓] Navigate │ [Enter] Run │ [C] Config │ [S] Save TOML │ [Q] Quit
```

---

## Highlights

- **Pure Lua & Zero C Dependencies**: Runs seamlessly across Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT with zero compilation step.
- **Agent Skills Discovery & Sync**: Real-time discovery, inspection, and syncing of Agent Skills (`SKILL.md`) across all AI agents (`~/.agents/skills`, `~/.claude/skills`, `~/.config/opencode/skills`, or any custom configured directory).
- **Interactive MCP Configuration**: Configure arguments, environment variables, API keys, and remote URLs per agent or broadcast to all agents directly in the TUI (`[C]`).
- **Zero-Install Ephemeral Execution**: MCP servers run on-demand via isolated FIFO coprocesses (`npx -y`, `uvx`, docker). No global npm or python environment pollution.
- **Auto-Cleaning History**: Every execution session is tracked in an ephemeral history ledger with execution duration, tool count, and status. Automatically purges old records or cleans on-demand.
- **Multi-Marketplace Hub**: Dynamic discovery aggregating servers from official Model Context Protocol registries and awesome-mcp repositories with zero hardcoded catalogs.
- **Universal AI Agent Environment Sync**: One-key install or removal of MCP servers and Skills across all local AI agent environments with schema auto-translation.
- **Hybrid TOML Engine**: Pure Lua TOML parser and serializer. Edit configurations directly in the TUI with live file sync and environment variable interpolation (`${ENV_VAR}`).
- **Native Multi-AI Synthesis**: Direct tool-calling integration with ZenMux, OpenRouter, DeepSeek, and local LLM endpoints (Ollama/vLLM). The AI receives MCP tool schemas and executes live tool invocations.
- **Strict Quality Pipeline**: Stylua formatting, Luacheck linting, and Teal (`tl`) typechecked definitions.

---

## Installation & Quick Start

### Quick One-Liner Install

#### Linux & macOS (cURL / Bash)
```bash
curl -fsSL https://raw.githubusercontent.com/nationdex/ai-bassmachine/main/install.sh | bash
```

#### Windows (PowerShell 5.1 or 7+)
```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; irm https://raw.githubusercontent.com/nationdex/ai-bassmachine/main/install.ps1 | iex
```
The installer writes `ai-bassmachine.cmd` (and `mcp-bassmachine.cmd` for compatibility) into your user path.

---

### Manual Clone

```bash
git clone https://github.com/nationdex/ai-bassmachine.git
cd ai-bassmachine

# Launch interactive TUI
./bin/ai-bassmachine
```

### CLI Mode
```bash
# Run preflight verification test
./bin/ai-bassmachine test

# Discover and list Agent Skills across environments
./bin/ai-bassmachine skills

# Create or install an Agent Skill to all agents (or specify target)
./bin/ai-bassmachine skill-add my-skill "Quick code reviewer skill" all

# Broadcast / sync a skill to all agents
./bin/ai-bassmachine skill-sync my-skill

# Run an MCP server ephemerally and introspect tools
./bin/ai-bassmachine run "npx -y @modelcontextprotocol/server-filesystem /tmp"

# Configure an MCP server's environment variable (e.g. API key) across agents
./bin/ai-bassmachine env-config github GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxx all

# List indexed MCPs across marketplaces
./bin/ai-bassmachine list

# Inspect ephemeral run history
./bin/ai-bassmachine history

# Clear session history
./bin/ai-bassmachine clean-history

# Check active TOML configuration
./bin/ai-bassmachine check-config

# Inspect MCP servers across all AI agent environments
./bin/ai-bassmachine env-list

# Broadcast/Install an existent MCP across ALL AI agents
./bin/ai-bassmachine env-sync uizze

# Install an MCP server into all AI agents at once (or specify target)
./bin/ai-bassmachine env-add my-server "uvx mcp-server-git --repository /tmp" all

# Remove an MCP server from all AI agents
./bin/ai-bassmachine env-remove my-server all
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

### Setting or changing an API key

- **In the TUI:** Settings (tab 5) -> pick the AI service, then the **API Key** row -> `Enter`, paste the key (it is hidden while typing). Empty + `Enter` removes it. The row shows only a masked value and where it came from.
- **Where it is stored:** `~/.config/ai-bassmachine/secrets.json` (`%USERPROFILE%\.config\ai-bassmachine\secrets.json` on Windows), outside the project folder, mode 600 on Linux/macOS. On Windows it relies on your user profile's permissions, not encryption.
- **Precedence:** environment variable (`ZENMUX_API_KEY`, ...) > secrets file. The TUI tells you when an env var is overriding a stored key.
- **CLI:** `ai-bassmachine keys` lists each provider's source and masked key; `ai-bassmachine clear-key <provider>` removes a stored key.
- **Rotating a leaked key:** revoke it at the provider, remove any old `ZENMUX_API_KEY` environment variable, then set the new one as above. A plaintext key found in `bassmachine.toml` (older versions wrote it there) is removed automatically on startup.

### API key safety

- Keys live in environment variables (`ZENMUX_API_KEY`, `OPENAI_API_KEY`, ...). `bassmachine.toml` keeps only `${ENV_VAR}` placeholders; `save()` never writes a resolved key and rewrites any literal key back to a placeholder.
- Requests go through a private (mode 600) curl config file, so keys never appear in `ps` output or URLs.
- Enable the secret-scan pre-commit hook once per clone: `git config core.hooksPath .githooks`. CI runs `scripts/secret-scan.sh` too.
- Pin installs with `AI_BASSMACHINE_REF=<tag> curl ... | bash`.

## TUI Keyboard Navigation

| Key | Action |
|---|---|
| `1` - `7` | Switch active tab (Marketplaces, Test & Run, Skills, AI Synth, History, Settings, Agent Sync) |
| `Tab` | Cycle next tab |
| `↑` / `↓` | Navigate list items and menu options |
| `Enter` | Launch ephemeral run (Tab 1), Trigger AI synthesis (Tab 4), Edit Setting (Tab 6) |
| `C` | Configure MCP arguments & environment variables (Tab 1 & Tab 7) |
| `I` | Quick install selected Marketplace MCP to ALL AI Agents (Tab 1) |
| `/` | Live search / keyword filter for MCPs (Tab 1) or Skills (Tab 3) |
| `P` | Toggle Free / Paid MCP filter in Marketplace (Tab 1) |
| `S` | Sync/Broadcast selected MCP (Tab 7) or Skill (Tab 3) across all agents; Save TOML (Tab 6) |
| `A` | Add/Create custom MCP (Tab 7) or Agent Skill (Tab 3) |
| `D` | Remove selected MCP or Skill from agent environment(s) |
| `U` | Remove/Purge selected MCP from ALL AI agents (Tab 7: Agent Sync) |
| `R` | Sync live MCP marketplaces across Official, Punkpeye, Wong2, and Appcypher (Tab 1) |
| `Space` | Toggle boolean values in Settings (Tab 6) |
| `C` | Clean all ephemeral session history (Tab 5) |
| `X` | Clean stale sessions older than retention limit (Tab 5) |
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
ai-bassmachine/
├── bin/
│   ├── ai-bassmachine              # Primary executable launcher
│   └── mcp-bassmachine             # Compatibility wrapper
├── src/
│   ├── main.lua                    # TUI & CLI entrypoint
│   ├── loader.lua                  # Cross-version module searcher
│   ├── config/
│   │   ├── toml.lua                # Pure Lua TOML parser & encoder
│   │   ├── manager.lua             # Hybrid runtime configuration manager
│   │   └── secrets.lua             # Isolated user secrets store
│   ├── skills/
│   │   └── manager.lua             # Dynamic Agent Skills discovery & sync
│   ├── mcp/
│   │   ├── client.lua              # JSON-RPC 2.0 MCP client
│   │   ├── runner.lua              # Ephemeral FIFO coprocess runner
│   │   └── history.lua             # Session tracker with auto-cleanup
│   ├── marketplace/
│   │   └── registry.lua            # Dynamic multi-registry aggregator & search
│   ├── env/
│   │   └── manager.lua             # Multi-agent environment sync & config
│   ├── ai/
│   │   └── provider.lua            # Multi-AI synthesis (ZenMux, OpenRouter, etc.)
│   ├── ui/
│   │   ├── engine.lua              # ANSI terminal engine & bass visualizer
│   │   ├── widgets.lua             # Reusable UI component library
│   │   └── views.lua               # Views (Marketplaces, Test, Skills, AI, History, TOML, Agent Sync)
│   └── utils/
│       ├── json.lua                # Pure Lua JSON parser/encoder
│       └── term.lua                # ANSI sequences, raw mode, keyboard events
├── types/
│   └── ai_bassmachine.d.tl         # Teal type definitions
├── tests/
│   ├── test_skills_manager.lua
│   ├── test_env_manager.lua
│   ├── test_tui_mcp_config.lua
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
└── ai-bassmachine-0.1.0-1.rockspec # LuaRocks package definition
```

---

## License

Apache License 2.0 © (NDS) Nationdex Solutions

