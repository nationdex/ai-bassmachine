-- MCP Bass Machine - Multi-Marketplace MCP Registry
-- Fetches and searches MCP servers from Smithery, Glama, Awesome-MCP, and MCP Index.

local json = require("mcp-bassmachine.utils.json")

local Registry = {}
Registry.__index = Registry

local CURATED_CATALOG = {
  {
    id = "mcp-filesystem",
    name = "Filesystem MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Secure direct filesystem access with configurable read/write boundaries.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-filesystem", "/tmp" },
    tags = { "filesystem", "official", "io" },
    category = "Utilities",
  },
  {
    id = "mcp-fetch",
    name = "Fetch / Web MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Converts any web page or REST API into clean markdown and structured resources.",
    command = "uvx",
    args = { "mcp-server-fetch" },
    tags = { "web", "fetch", "http", "official" },
    category = "Web",
  },
  {
    id = "mcp-sqlite",
    name = "SQLite Explorer",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Introspect and query local SQLite databases with automated schema extraction.",
    command = "uvx",
    args = { "mcp-server-sqlite", "--db-path", "/tmp/bass.db" },
    tags = { "database", "sqlite", "sql" },
    category = "Database",
  },
  {
    id = "mcp-git",
    name = "Git Repository MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Read repository trees, inspect git logs, diff commits, and inspect git branches.",
    command = "uvx",
    args = { "mcp-server-git" },
    tags = { "git", "vcs", "code" },
    category = "Development",
  },
  {
    id = "mcp-brave-search",
    name = "Brave Search MCP",
    author = "Model Context Protocol Official",
    source = "smithery",
    description = "Real-time web and local search using the privacy-focused Brave Search API.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-brave-search" },
    tags = { "search", "web", "brave" },
    category = "Search",
  },
  {
    id = "mcp-memory",
    name = "Memory / Knowledge Graph",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Graph-based long-term associative memory for autonomous agents.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-memory" },
    tags = { "memory", "graph", "ai" },
    category = "AI",
  },
  {
    id = "mcp-postgres",
    name = "PostgreSQL Inspector",
    author = "Model Context Protocol Official",
    source = "glama",
    description = "Full schema introspection, table definitions, and parameterized query execution.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/dev" },
    tags = { "database", "postgres", "sql" },
    category = "Database",
  },
  {
    id = "mcp-everything",
    name = "Everything Reference Server",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Comprehensive reference implementation exercising tools, prompts, and resources.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-everything" },
    tags = { "test", "reference", "mcp" },
    category = "Testing",
  },
  {
    id = "mcp-github",
    name = "GitHub API MCP",
    author = "Model Context Protocol Official",
    source = "awesome-mcp",
    description = "Inspect pull requests, issues, commits, repositories, and workflow runs.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-github" },
    tags = { "github", "git", "api" },
    category = "Development",
  },
  {
    id = "mcp-puppeteer",
    name = "Puppeteer Browser Automation",
    author = "Model Context Protocol Official",
    source = "smithery",
    description = "Automate headless Chromium browsing, take screenshots, and evaluate scripts.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-puppeteer" },
    tags = { "browser", "automation", "puppeteer" },
    category = "Web",
  },
}

function Registry.new(config)
  local self = setmetatable({}, Registry)
  self.config = config
  self.cache = {}
  self.cached_at = 0
  self.is_fetching = false
  return self
end

function Registry.fetch_live_marketplace(url, source_name)
  local cmd = string.format("curl -s -m 5 '%s' 2>/dev/null", url)
  local f = io.popen(cmd, "r")
  if not f then
    return {}
  end
  local body = f:read("*a")
  f:close()

  if not body or #body < 10 then
    return {}
  end

  local parsed = json.decode(body)
  if not parsed or type(parsed) ~= "table" then
    return {}
  end

  local results = {}
  -- Handle list or nested object results
  local items = parsed.items or parsed.servers or parsed
  if type(items) == "table" then
    for idx, item in ipairs(items) do
      if type(item) == "table" and item.name then
        table.insert(results, {
          id = item.id or (source_name .. "-" .. tostring(idx)),
          name = item.name,
          author = item.author or item.vendor or source_name,
          source = source_name,
          description = item.description or "No description provided.",
          command = item.command or "npx",
          args = item.args or { "-y", item.name },
          tags = item.tags or { source_name },
          category = item.category or "General",
        })
      end
    end
  end
  return results
end

function Registry:get_all()
  local items = {}
  -- Always include curated baseline
  for _, item in ipairs(CURATED_CATALOG) do
    table.insert(items, item)
  end

  -- Add cached remote marketplace results if available
  for _, item in ipairs(self.cache) do
    table.insert(items, item)
  end

  return items
end

function Registry:search(query, category, source_filter)
  local all = self:get_all()
  if
    (not query or query == "")
    and (not category or category == "All")
    and (not source_filter or source_filter == "All")
  then
    return all
  end

  query = query and query:lower() or ""
  local filtered = {}

  for _, item in ipairs(all) do
    local match = true
    if category and category ~= "All" and item.category ~= category then
      match = false
    end
    if source_filter and source_filter ~= "All" and item.source ~= source_filter then
      match = false
    end
    if query ~= "" then
      local n_match = item.name:lower():find(query, 1, true)
      local d_match = item.description:lower():find(query, 1, true)
      local t_match = false
      if item.tags then
        for _, tag in ipairs(item.tags) do
          if tag:lower():find(query, 1, true) then
            t_match = true
            break
          end
        end
      end
      if not (n_match or d_match or t_match) then
        match = false
      end
    end

    if match then
      table.insert(filtered, item)
    end
  end

  return filtered
end

function Registry:refresh_marketplaces_async()
  -- Fetch from official MCP catalog and registries in background
  local smithery_url = "https://registry.smithery.ai/api/servers"
  local remote_smithery = self:fetch_live_marketplace(smithery_url, "smithery")
  for _, it in ipairs(remote_smithery) do
    table.insert(self.cache, it)
  end
  self.cached_at = os.time()
end

return Registry
