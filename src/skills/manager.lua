-- AI Bass Machine - Pure Dynamic Agent Skills Engine & Marketplace
-- 100% dynamic: discovers, inspects, installs, syncs, and removes Agent Skills
-- by reading real SKILL.md files from filesystem or live registries with zero hardcoded catalogs.

local json = require("ai-bassmachine.utils.json")
local term = require("ai-bassmachine.utils.term")

local SkillManager = {}
SkillManager.__index = SkillManager

local function get_home()
  return term.get_home_dir()
end

-- Parse frontmatter from any SKILL.md dynamically
function SkillManager.parse_skill_md(content, fallback_name)
  if not content or #content == 0 then
    return { name = fallback_name or "unnamed", description = "", body = "" }
  end

  local meta = {}
  local body = content

  if content:sub(1, 3) == "---" then
    local end_pos = content:find("\n---", 4, true)
    if end_pos then
      local yaml_block = content:sub(4, end_pos)
      body = content:sub(end_pos + 4):gsub("^[\r\n]+", "")
      for line in yaml_block:gmatch("[^\r\n]+") do
        local k, v = line:match("^([%w_%-]+)%s*:%s*(.*)$")
        if k and v then
          v = v:gsub("^[\"']", ""):gsub("[\"']$", ""):gsub("^%s+", ""):gsub("%s+$", "")
          meta[k] = v
        end
      end
    end
  end

  meta.body = body
  if not meta.name or #meta.name == 0 then
    meta.name = body:match("^#%s+([^\r\n]+)") or fallback_name or "custom-skill"
  end
  if not meta.description or #meta.description == 0 then
    local first_line = body:match("^[^\r\n#]+") or ""
    meta.description = first_line:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 140)
  end

  return meta
end

local function build_skill_targets(config)
  local home = get_home()
  local targets = {
    {
      id = "agents",
      name = "Global Agent Skills",
      dir = home .. "/.agents/skills",
    },
    {
      id = "claude",
      name = "Claude Code Skills",
      dir = home .. "/.claude/skills",
    },
    {
      id = "opencode",
      name = "OpenCode Skills",
      dir = home .. "/.config/opencode/skills",
    },
  }

  -- Merge any user-defined skill directories from config
  if config and config.get then
    local custom = config:get("skills.custom_directories")
    if custom and type(custom) == "table" then
      for idx, cdir in ipairs(custom) do
        table.insert(targets, {
          id = "custom_" .. tostring(idx),
          name = "Custom Skills (" .. tostring(cdir) .. ")",
          dir = tostring(cdir):gsub("^~", home),
        })
      end
    end
  end

  return targets
end

function SkillManager.new(config)
  local self = setmetatable({}, SkillManager)
  self.config = config
  self.targets = build_skill_targets(config)
  self.cache_file = get_home() .. "/.bassmachine_skills_cache.json"
  self.marketplace_cache = {}
  self.cached_at = 0
  self:load_cache_from_disk()

  -- Auto-fetch remote skills marketplace on cold start if cache is empty
  if #self.marketplace_cache == 0 then
    self:refresh_marketplace()
  end

  return self
end

function SkillManager:load_cache_from_disk()
  local f = io.open(self.cache_file, "r")
  if f then
    local content = f:read("*a")
    f:close()
    if content and #content > 0 then
      local parsed = json.decode(content)
      if type(parsed) == "table" and parsed.items then
        self.marketplace_cache = parsed.items
        self.cached_at = parsed.cached_at or 0
      end
    end
  end
end

function SkillManager:save_cache_to_disk()
  local f = io.open(self.cache_file, "w")
  if f then
    local payload = json.encode({
      cached_at = os.time(),
      items = self.marketplace_cache,
    })
    f:write(payload)
    f:close()
  end
end

-- 1. Fetch official Anthropic Skills repo via GitHub Trees API
function SkillManager.fetch_anthropic_skills()
  local cmd = "curl -s -m 8 'https://api.github.com/repos/anthropics/skills/git/trees/main?recursive=1' 2>/dev/null"
  local f = term.safe_popen(cmd)
  if not f then
    return {}
  end
  local body = f:read("*a")
  f:close()

  if not body or #body < 50 then
    return {}
  end

  local parsed = json.decode(body)
  if not parsed or type(parsed) ~= "table" or not parsed.tree then
    return {}
  end

  local results = {}
  local seen = {}

  for _, item in ipairs(parsed.tree) do
    if item.path and item.path:match("^skills/[^/]+/SKILL%.md$") then
      local sname = item.path:match("^skills/([^/]+)/SKILL%.md$")
      if sname and not seen[sname] then
        seen[sname] = true
        local raw_url = "https://raw.githubusercontent.com/anthropics/skills/main/" .. item.path
        table.insert(results, {
          id = "anthropic-" .. sname,
          name = sname,
          author = "Anthropic Official",
          source = "anthropic/skills",
          url = "https://github.com/anthropics/skills/tree/main/skills/" .. sname,
          raw_url = raw_url,
          category = "Official Skills",
          description = "Official skill for " .. sname,
        })
      end
    end
  end

  return results
end

-- 2. Fetch community ECC (Everything Claude Code / OpenCode) skills repo
function SkillManager.fetch_ecc_skills()
  local cmd = "curl -s -m 8 'https://api.github.com/repos/affaan-m/ECC/git/trees/main?recursive=1' 2>/dev/null"
  local f = term.safe_popen(cmd)
  if not f then
    return {}
  end
  local body = f:read("*a")
  f:close()

  if not body or #body < 50 then
    return {}
  end

  local parsed = json.decode(body)
  if not parsed or type(parsed) ~= "table" or not parsed.tree then
    return {}
  end

  local results = {}
  local seen = {}

  for _, item in ipairs(parsed.tree) do
    if item.path and item.path:match("^skills/[^/]+/SKILL%.md$") then
      local sname = item.path:match("^skills/([^/]+)/SKILL%.md$")
      if sname and not seen[sname] then
        seen[sname] = true
        local raw_url = "https://raw.githubusercontent.com/affaan-m/ECC/main/" .. item.path
        table.insert(results, {
          id = "ecc-" .. sname,
          name = sname,
          author = "affaan-m / ECC",
          source = "ecc-skills",
          url = "https://github.com/affaan-m/ECC/tree/main/skills/" .. sname,
          raw_url = raw_url,
          category = "Engineering & Harness",
          description = "ECC agent skill: " .. sname,
        })
      end
    end
  end

  return results
end

-- Refresh marketplace cache from live GitHub sources
function SkillManager:refresh_marketplace()
  local anthropic_skills = self.fetch_anthropic_skills()
  local ecc_skills = self.fetch_ecc_skills()

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

  add_list(anthropic_skills)
  add_list(ecc_skills)

  if #combined > 0 then
    self.marketplace_cache = combined
    self.cached_at = os.time()
    self:save_cache_to_disk()
    return true, #combined
  end
  return false, 0
end

-- Get all marketplace skills (with search filter)
function SkillManager:get_marketplace_skills(query)
  local all = self.marketplace_cache or {}
  if not query or query == "" then
    return all
  end

  query = query:lower()
  local filtered = {}
  for _, sk in ipairs(all) do
    local match = (sk.name and sk.name:lower():find(query, 1, true))
      or (sk.description and sk.description:lower():find(query, 1, true))
      or (sk.author and sk.author:lower():find(query, 1, true))
      or (sk.category and sk.category:lower():find(query, 1, true))
    if match then
      table.insert(filtered, sk)
    end
  end
  return filtered
end

-- Install a skill directly from the marketplace URL into agent environments
function SkillManager:install_from_marketplace(skill_item, target_id)
  if not skill_item or not skill_item.raw_url then
    return false, "Missing raw_url for skill"
  end

  local cmd = string.format("curl -s -m 8 %s 2>/dev/null", term.shell_quote(skill_item.raw_url))
  local f = term.safe_popen(cmd)
  if not f then
    return false, "Failed to download skill content"
  end
  local content = f:read("*a")
  f:close()

  if not content or #content == 0 or content:find("404: Not Found", 1, true) then
    return false, "Could not fetch SKILL.md from repository"
  end

  local results = self:install_skill(skill_item.name, content, target_id or "all")
  return true, results, content
end

function SkillManager:get_targets()
  return self.targets
end

local function read_file(path)
  local f = io.open(path, "r")
  if not f then
    return nil
  end
  local content = f:read("*a")
  f:close()
  return content
end

-- Dynamically scan a target directory for skill directories containing SKILL.md
local function scan_dir_for_skills(base_dir)
  local skills = {}
  if not base_dir or #base_dir == 0 then
    return skills
  end

  local cmd
  if term.is_windows then
    cmd = string.format('cmd.exe /c "dir /b /ad \\"%s\\"" 2>nul', base_dir:gsub("/", "\\"))
  else
    cmd = string.format("ls -1 %s 2>/dev/null", term.shell_quote(base_dir))
  end

  local pipe = term.safe_popen(cmd)
  if not pipe then
    return skills
  end

  for line in pipe:lines() do
    local sname = line:gsub("[\r\n]+", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if #sname > 0 and not sname:match("^%.") then
      local skill_md = base_dir .. "/" .. sname .. "/SKILL.md"
      local content = read_file(skill_md)
      if content then
        local meta = SkillManager.parse_skill_md(content, sname)
        skills[sname] = {
          name = meta.name or sname,
          dir_name = sname,
          path = skill_md,
          description = meta.description or "Dynamic Agent Skill",
          raw = content,
          body = meta.body or content,
        }
      end
    end
  end
  pipe:close()

  return skills
end

-- List all dynamically discovered skills across all agent environments
function SkillManager:list_all()
  local list = {}
  local seen = {}

  for _, target in ipairs(self.targets) do
    local found = scan_dir_for_skills(target.dir)
    for sname, sdata in pairs(found) do
      if not seen[sname] then
        seen[sname] = {
          name = sdata.name,
          dir_name = sdata.dir_name,
          description = sdata.description,
          path = sdata.path,
          raw = sdata.raw,
          body = sdata.body,
          installed_in = { target.id },
        }
      else
        table.insert(seen[sname].installed_in, target.id)
      end
    end
  end

  for _, sk in pairs(seen) do
    table.insert(list, sk)
  end
  table.sort(list, function(a, b)
    return a.name:lower() < b.name:lower()
  end)

  return list
end

-- Install / create a dynamic skill in a specific target agent or all agents
function SkillManager:install_skill(skill_name, content, target_id)
  local clean_name = skill_name:lower():gsub("[^%w_%-]", "-")
  if not content or #content == 0 then
    content = string.format("---\nname: %s\ndescription: Custom agent skill\n---\n\n# %s\n", skill_name, skill_name)
  end

  local results = {}
  for _, target in ipairs(self.targets) do
    if not target_id or target_id == "all" or target.id == target_id then
      local dest_dir = target.dir .. "/" .. clean_name
      term.mkdir_p(dest_dir)
      local dest_file = dest_dir .. "/SKILL.md"
      local f = io.open(dest_file, "w")
      if f then
        f:write(content)
        f:close()
        table.insert(results, {
          target = target.id,
          name = target.name,
          path = dest_file,
          success = true,
        })
      else
        table.insert(results, {
          target = target.id,
          name = target.name,
          path = dest_file,
          success = false,
          error = "Failed to write " .. dest_file,
        })
      end
    end
  end

  return results
end

-- Delete a skill from a specific target agent or all agents
function SkillManager:remove_skill(skill_name, target_id)
  local clean_name = skill_name:lower():gsub("[^%w_%-]", "-")
  local results = {}

  for _, target in ipairs(self.targets) do
    if not target_id or target_id == "all" or target.id == target_id then
      local skill_dir = target.dir .. "/" .. clean_name
      local skill_file = skill_dir .. "/SKILL.md"
      os.remove(skill_file)
      if term.is_windows then
        os.execute(string.format('cmd.exe /c "rd /s /q \\"%s\\"" 2>nul', skill_dir:gsub("/", "\\")))
      else
        os.execute(string.format("rm -rf %s 2>/dev/null", term.shell_quote(skill_dir)))
      end
      local removed = true

      table.insert(results, {
        target = target.id,
        name = target.name,
        path = skill_dir,
        success = true,
        removed = removed,
      })
    end
  end

  return results
end

-- Broadcast / sync an existing skill across all agent environments
function SkillManager:sync_skill_to_all(skill_name)
  local all_skills = self:list_all()
  local target_sname = skill_name:lower()
  local found_content = nil

  for _, sk in ipairs(all_skills) do
    if sk.name:lower() == target_sname or sk.dir_name:lower() == target_sname then
      found_content = sk.raw or read_file(sk.path)
      break
    end
  end

  if not found_content then
    return false, "Skill '" .. skill_name .. "' not found in any agent environment."
  end

  local results = self:install_skill(skill_name, found_content, "all")
  return true, results
end

return SkillManager
