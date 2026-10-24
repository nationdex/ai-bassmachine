-- MCP Bass Machine - Multi-Marketplace MCP Registry
-- Fetches and searches MCP servers from Official Registry, Punkpeye Awesome-MCP,
-- Wong2 Awesome-MCP, and Appcypher Awesome-MCP registries.

local json = require("mcp-bassmachine.utils.json")

local Registry = {}
Registry.__index = Registry

local CURATED_CATALOG = {
  -- Core Official MCPs
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
    id = "mcp-postgres",
    name = "PostgreSQL Inspector",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Full schema introspection, table definitions, and parameterized query execution.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/dev" },
    tags = { "database", "postgres", "sql" },
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
    id = "mcp-github",
    name = "GitHub API MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Inspect pull requests, issues, commits, repositories, and workflow runs.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-github" },
    tags = { "github", "git", "api" },
    category = "Development",
  },
  {
    id = "mcp-gitlab",
    name = "GitLab API MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Interact with GitLab projects, merge requests, CI pipelines, and issues.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-gitlab" },
    tags = { "gitlab", "git", "ci" },
    category = "Development",
  },
  {
    id = "mcp-brave-search",
    name = "Brave Search MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Real-time web and local search using the privacy-focused Brave Search API.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-brave-search" },
    tags = { "search", "web", "brave" },
    category = "Search",
  },
  {
    id = "mcp-google-maps",
    name = "Google Maps MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Location services, geocoding, places discovery, and turn-by-turn routing.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-google-maps" },
    tags = { "maps", "location", "geo" },
    category = "Web",
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
    id = "mcp-puppeteer",
    name = "Puppeteer Automation",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Headless Chromium browser automation, screenshots, and DOM scraping.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-puppeteer" },
    tags = { "browser", "automation", "puppeteer" },
    category = "Web",
  },
  {
    id = "mcp-slack",
    name = "Slack MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Interact with Slack channels, post messages, and read thread replies.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-slack" },
    tags = { "slack", "chat", "communication" },
    category = "Communication",
  },
  {
    id = "mcp-sequential-thinking",
    name = "Sequential Thinking MCP",
    author = "Model Context Protocol Official",
    source = "official",
    description = "Dynamic multi-step reflective reasoning engine for complex agent problem solving.",
    command = "npx",
    args = { "-y", "@modelcontextprotocol/server-sequential-thinking" },
    tags = { "thinking", "reasoning", "ai" },
    category = "AI",
  },

  -- Cloud & Infrastructure
  {
    id = "mcp-docker",
    name = "Docker Engine MCP",
    author = "Community",
    source = "awesome-mcp",
    description = "Manage Docker containers, images, volumes, and networks via Docker daemon API.",
    command = "npx",
    args = { "-y", "docker-mcp" },
    tags = { "docker", "containers", "devops" },
    category = "DevOps",
  },
  {
    id = "mcp-kubernetes",
    name = "Kubernetes Cluster MCP",
    author = "Community",
    source = "awesome-mcp",
    description = "Inspect pods, services, deployments, and cluster logs through kubectl contexts.",
    command = "npx",
    args = { "-y", "kubernetes-mcp-server" },
    tags = { "k8s", "kubernetes", "cloud" },
    category = "DevOps",
  },
  {
    id = "mcp-aws-s3",
    name = "AWS S3 Storage MCP",
    author = "Community",
    source = "awesome-mcp",
    description = "Browse, upload, download, and manage objects and buckets in Amazon S3.",
    command = "uvx",
    args = { "mcp-server-s3" },
    tags = { "aws", "s3", "cloud", "storage" },
    category = "DevOps",
  },
  {
    id = "mcp-redis",
    name = "Redis Key-Value MCP",
    author = "Redis Official",
    source = "awesome-mcp",
    description = "Query keys, inspect data structures, run Redis commands, and monitor memory.",
    command = "npx",
    args = { "-y", "@redis/mcp-server-redis" },
    tags = { "redis", "database", "cache" },
    category = "Database",
  },
  {
    id = "mcp-elasticsearch",
    name = "Elasticsearch MCP",
    author = "Community",
    source = "awesome-mcp",
    description = "Search indices, execute Lucene/DSL queries, and inspect cluster health.",
    command = "npx",
    args = { "-y", "mcp-server-elasticsearch" },
    tags = { "elasticsearch", "search", "database" },
    category = "Database",
  },

  -- Productivity & Knowledge
  {
    id = "mcp-notion",
    name = "Notion Workspace MCP",
    author = "Community",
    source = "smithery",
    description = "Query Notion databases, search pages, append blocks, and manage tasks.",
    command = "npx",
    args = { "-y", "@notionhq/notion-mcp" },
    tags = { "notion", "productivity", "docs" },
    category = "Productivity",
  },
  {
    id = "mcp-linear",
    name = "Linear Issue Tracker",
    author = "Jerhadf",
    source = "glama",
    description = "Search issues, update issue status, create tickets, and manage project sprints.",
    command = "npx",
    args = { "-y", "mcp-server-linear" },
    tags = { "linear", "project", "issues" },
    category = "Productivity",
  },
  {
    id = "mcp-jira",
    name = "Atlassian Jira MCP",
    author = "Community",
    source = "awesome-mcp",
    description = "Introspect Jira boards, create tickets, transition states, and search JQL.",
    command = "npx",
    args = { "-y", "mcp-jira-server" },
    tags = { "jira", "atlassian", "issues" },
    category = "Productivity",
  },
  {
    id = "mcp-obsidian",
    name = "Obsidian Markdown Vault",
    author = "Community",
    source = "awesome-mcp",
    description = "Read, search, backlink, and modify notes inside local Obsidian vaults.",
    command = "npx",
    args = { "-y", "mcp-obsidian-server" },
    tags = { "obsidian", "notes", "markdown" },
    category = "Productivity",
  },
  {
    id = "mcp-todoist",
    name = "Todoist Task Manager",
    author = "Community",
    source = "awesome-mcp",
    description = "Sync tasks, manage due dates, and organize projects via Todoist REST API.",
    command = "uvx",
    args = { "todoist-mcp" },
    tags = { "todoist", "tasks", "productivity" },
    category = "Productivity",
  },

  -- Search & Web
  {
    id = "mcp-playwright",
    name = "Playwright Browser MCP",
    author = "Community",
    source = "smithery",
    description = "Automate web interaction, click buttons, fill forms, and snapshot web apps.",
    command = "npx",
    args = { "-y", "@executeautomation/playwright-mcp-server" },
    tags = { "playwright", "browser", "automation" },
    category = "Web",
  },
  {
    id = "mcp-exa-search",
    name = "Exa Neural Search MCP",
    author = "Exa AI",
    source = "glama",
    description = "Neural search engine built for LLMs to find live web documents and research papers.",
    command = "npx",
    args = { "-y", "exa-mcp-server" },
    tags = { "search", "exa", "ai" },
    category = "Search",
  },
  {
    id = "mcp-tavily",
    name = "Tavily AI Search MCP",
    author = "Tavily",
    source = "glama",
    description = "Search engine optimized specifically for LLMs and autonomous AI agents.",
    command = "npx",
    args = { "-y", "tavily-mcp" },
    tags = { "search", "tavily", "ai" },
    category = "Search",
  },
  {
    id = "mcp-context7",
    name = "Context7 Live Docs MCP",
    author = "Upstash",
    source = "smithery",
    description = "Search and fetch up-to-date documentation and code samples for popular libraries.",
    command = "npx",
    args = { "-y", "@upstash/context7-mcp" },
    tags = { "docs", "documentation", "reference" },
    category = "Development",
  },
}

function Registry.new(config)
  local self = setmetatable({}, Registry)
  self.config = config
  self.cache_file = os.getenv("HOME") .. "/.bassmachine_mcp_cache.json"
  self.cache = {}
  self.cached_at = 0
  self.is_fetching = false
  self:load_cache_from_disk()
  return self
end

function Registry:load_cache_from_disk()
  local f = io.open(self.cache_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content and #content > 0 then
      local parsed = json.decode(content)
      if type(parsed) == "table" and parsed.items then
        self.cache = parsed.items
        self.cached_at = parsed.cached_at or 0
      end
    end
  end
end

function Registry:save_cache_to_disk()
  local f = io.open(self.cache_file, "w")
  if f then
    local payload = json.encode({
      cached_at = os.time(),
      items = self.cache,
    })
    f:write(payload)
    f:close()
  end
end

-- 1. Official MCP Registry (JSON API)
function Registry.fetch_official_registry()
  local cmd = "curl -s -m 6 'https://registry.modelcontextprotocol.io/v0.1/servers' 2>/dev/null"
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
  if not parsed or type(parsed) ~= "table" or not parsed.servers then
    return {}
  end

  local results = {}
  local seen = {}

  for _, entry in ipairs(parsed.servers) do
    local s = entry.server
    if s and s.name and not seen[s.name] then
      seen[s.name] = true
      local display_name = s.title or s.name
      local remotes = s.remotes or {}
      local remote_url = nil
      if #remotes > 0 and remotes[1].url then
        remote_url = remotes[1].url
      end

      local command = "npx"
      local args = { "-y", s.name }
      if remote_url then
        command = "curl"
        args = { "-N", remote_url }
      end

      local cat = "Official Registry"
      local name_l = s.name:lower()
      if name_l:match("search") or name_l:match("find") then
        cat = "Search"
      elseif name_l:match("ai") or name_l:match("inference") or name_l:match("agent") then
        cat = "AI"
      elseif name_l:match("db") or name_l:match("sql") or name_l:match("data") then
        cat = "Database"
      elseif name_l:match("web") or name_l:match("browser") or name_l:match("scrape") then
        cat = "Web"
      end

      table.insert(results, {
        id = "official-" .. (s.name:gsub("[^%w_%-]", "-")),
        name = display_name,
        author = s.name:match("^([^/]+)") or "Official Registry",
        source = "official-reg",
        description = s.description or ("Official MCP registry server: " .. s.name),
        command = command,
        args = args,
        url = remote_url,
        tags = { "official", "registry", s.version or "1.0.0" },
        category = cat,
      })
    end
  end

  return results
end

-- 2. Punkpeye Awesome-MCP Registry
function Registry.fetch_punkpeye_mcp()
  local cmd = "curl -s -m 8 'https://raw.githubusercontent.com/punkpeye/awesome-mcp-servers/main/README.md' 2>/dev/null"
  local f = io.popen(cmd, "r")
  if not f then
    return {}
  end
  local text = f:read("*a")
  f:close()

  if not text or #text < 100 then
    return {}
  end

  local results = {}
  local seen = {}
  local cur_category = "Community"

  for line in text:gmatch("[^\r\n]+") do
    local cat_header = line:match("^###%s+(.+)$") or line:match("^##%s+(.+)$")
    if cat_header then
      local clean_cat = cat_header:gsub("<[^>]+>", ""):gsub("[^%w%s%-_/]", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if #clean_cat > 0 and not clean_cat:find("Table of", 1, true) then
        cur_category = clean_cat
      end
    end

    local name, url, rest = line:match("^%-%s+%[([^%]]+)%]%((https?://[^%)]+)%)%s*(.*)$")
    if
      name
      and url
      and not seen[name]
      and not name:find("Build your own", 1, true)
      and not name:find("awesome", 1, true)
    then
      seen[name] = true
      local clean_desc = rest:gsub("%[!%[[^%]]*%]%([^%)]*%)%]%s*", "")
      clean_desc = clean_desc:gsub("%([^%)]*%)%s*", "")
      clean_desc = clean_desc:gsub("[%z\1-\31\128-\255]+", " ")
      clean_desc = clean_desc:gsub("^[%s%-]+", ""):gsub("%s+$", "")
      if #clean_desc == 0 then
        clean_desc = "Community MCP Server for " .. name
      end

      local pkg_id = name:gsub("[^%w_%-]", "-"):lower()
      local cmd_name = name:match("/([^/]+)$") or name
      table.insert(results, {
        id = "awesome-" .. pkg_id,
        name = name,
        author = name:match("^([^/]+)") or "Community",
        source = "awesome-mcp",
        description = clean_desc:sub(1, 140),
        command = "npx",
        args = { "-y", cmd_name },
        url = url,
        tags = { "awesome", "community", cur_category },
        category = cur_category,
      })

      if #results >= 100 then
        break
      end
    end
  end

  return results
end

-- 3. Wong2 Awesome-MCP Registry
function Registry.fetch_wong2_mcp()
  local cmd = "curl -s -m 8 'https://raw.githubusercontent.com/wong2/awesome-mcp-servers/main/README.md' 2>/dev/null"
  local f = io.popen(cmd, "r")
  if not f then
    return {}
  end
  local text = f:read("*a")
  f:close()

  if not text or #text < 100 then
    return {}
  end

  local results = {}
  local seen = {}
  local cur_category = "Productivity"

  for line in text:gmatch("[^\r\n]+") do
    local cat_header = line:match("^###%s+(.+)$") or line:match("^##%s+(.+)$")
    if cat_header then
      local clean_cat = cat_header:gsub("<[^>]+>", ""):gsub("[^%w%s%-_/]", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if #clean_cat > 0 and not clean_cat:find("Sponsors", 1, true) then
        cur_category = clean_cat
      end
    end

    local name, url, rest = line:match("^%-%s+%*%*%[([^%]]+)%]%((https?://[^%)]+)%)%*%*%s*%-?%s*(.*)$")
    if name and url and not seen[name] then
      seen[name] = true
      local clean_desc = rest:gsub("%[!%[[^%]]*%]%([^%)]*%)%]%s*", "")
      clean_desc = clean_desc:gsub("%[[^%]]*%]%([^%)]*%)", "")
      clean_desc = clean_desc:gsub("[%z\1-\31\128-\255]+", " ")
      clean_desc = clean_desc:gsub("^[%s%-]+", ""):gsub("%s+$", "")
      if #clean_desc == 0 then
        clean_desc = "MCP Server for " .. name
      end

      local pkg_id = name:gsub("[^%w_%-]", "-"):lower()
      local cmd_name = name:match("/([^/]+)$") or name
      table.insert(results, {
        id = "wong2-" .. pkg_id,
        name = name,
        author = name:match("^([^/]+)") or "Wong2 Registry",
        source = "wong2-mcp",
        description = clean_desc:sub(1, 140),
        command = "npx",
        args = { "-y", cmd_name },
        url = url,
        tags = { "wong2", "registry", cur_category },
        category = cur_category,
      })

      if #results >= 100 then
        break
      end
    end
  end

  return results
end

-- 4. Appcypher Awesome-MCP Registry
function Registry.fetch_appcypher_mcp()
  local cmd =
    "curl -s -m 8 'https://raw.githubusercontent.com/appcypher/awesome-mcp-servers/main/README.md' 2>/dev/null"
  local f = io.popen(cmd, "r")
  if not f then
    return {}
  end
  local text = f:read("*a")
  f:close()

  if not text or #text < 100 then
    return {}
  end

  local results = {}
  local seen = {}
  local cur_category = "Utilities"

  for line in text:gmatch("[^\r\n]+") do
    local cat_header = line:match("^###%s+(.+)$") or line:match("^##%s+(.+)$")
    if cat_header then
      local clean_cat = cat_header:gsub("<[^>]+>", ""):gsub("[^%w%s%-_/]", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if #clean_cat > 0 then
        cur_category = clean_cat
      end
    end

    local name, url, rest = line:match("%[([^%]]+)%]%((https?://github%.com/[^%)]+)%)%s*%-?%s*(.*)$")
    if
      name
      and url
      and not seen[name]
      and not name:find("<img", 1, true)
      and not name:find("Claude", 1, true)
      and not name:find("Visual Studio", 1, true)
    then
      seen[name] = true
      local clean_desc = rest:gsub("<[^>]+>", "")
      clean_desc = clean_desc:gsub("%[!%[[^%]]*%]%([^%)]*%)%]%s*", "")
      clean_desc = clean_desc:gsub("[%z\1-\31\128-\255]+", " ")
      clean_desc = clean_desc:gsub("^[%s%-]+", ""):gsub("%s+$", "")
      if #clean_desc == 0 then
        clean_desc = "Server for " .. name
      end

      local pkg_id = name:gsub("[^%w_%-]", "-"):lower()
      local cmd_name = url:match("github%.com/[^/]+/([^/#%?]+)") or name
      table.insert(results, {
        id = "appcypher-" .. pkg_id,
        name = name,
        author = url:match("github%.com/([^/]+)") or "Community",
        source = "appcypher-mcp",
        description = clean_desc:sub(1, 140),
        command = "npx",
        args = { "-y", cmd_name },
        url = url,
        tags = { "appcypher", "community", cur_category },
        category = cur_category,
      })

      if #results >= 80 then
        break
      end
    end
  end

  return results
end

local function detect_server_pricing(item)
  if item.pricing then
    return item.pricing
  end
  local text = ((item.name or "") .. " " .. (item.description or "") .. " " .. table.concat(item.tags or {}, " ")):lower()

  -- Check for paid indicators (x402, pay-per-call, micropayments, paid intelligence, tokens, billing)
  if
    text:find("x402", 1, true)
    or text:find("pay%-per%-call")
    or text:find("pay per call", 1, true)
    or text:find("paid crypto", 1, true)
    or text:find("paid intelligence", 1, true)
    or text:find("micropayment", 1, true)
    or text:find("usdt", 1, true)
    or text:find("usdc", 1, true)
    or text:find("solana payments", 1, true)
    or text:find("subscription", 1, true)
    or text:find("commercial license", 1, true)
    or text:find("token cost", 1, true)
  then
    if
      not (text:find("free tier", 1, true) or text:find("100%% free", 1, true) or text:find("open source", 1, true))
    then
      return "Paid"
    end
  end
  return "Free"
end

function Registry:get_all()
  local items = {}
  local seen = {}

  -- 1. Always include curated baseline
  for _, item in ipairs(CURATED_CATALOG) do
    if not seen[item.name] then
      seen[item.name] = true
      item.pricing = item.pricing or detect_server_pricing(item)
      table.insert(items, item)
    end
  end

  -- 2. Add cached remote marketplace results
  for _, item in ipairs(self.cache) do
    if not seen[item.name] then
      seen[item.name] = true
      item.pricing = item.pricing or detect_server_pricing(item)
      table.insert(items, item)
    end
  end

  return items
end

function Registry:search(query, category, source_filter, pricing_filter)
  local all = self:get_all()
  if
    (not query or query == "")
    and (not category or category == "All")
    and (not source_filter or source_filter == "All")
    and (not pricing_filter or pricing_filter == "All")
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
    if pricing_filter and pricing_filter ~= "All" and (item.pricing or "Free") ~= pricing_filter then
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

function Registry:refresh_marketplaces()
  local official_servers = self.fetch_official_registry()
  local punkpeye_servers = self.fetch_punkpeye_mcp()
  local wong2_servers = self.fetch_wong2_mcp()
  local appcypher_servers = self.fetch_appcypher_mcp()

  local combined = {}
  local seen = {}

  local function add_list(list)
    for _, it in ipairs(list) do
      if not seen[it.name] then
        seen[it.name] = true
        table.insert(combined, it)
      end
    end
  end

  add_list(official_servers)
  add_list(punkpeye_servers)
  add_list(wong2_servers)
  add_list(appcypher_servers)

  if #combined > 0 then
    self.cache = combined
    self.cached_at = os.time()
    self:save_cache_to_disk()
    return true, #combined
  end
  return false, 0
end

return Registry
