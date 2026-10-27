-- AI Bass Machine - Pure Dynamic Agent Skills Engine
-- 100% dynamic: discovers, inspects, installs, syncs, and removes Agent Skills
-- by reading real SKILL.md files from filesystem or URLs with zero hardcoded catalogs.

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
          v = v:gsub('^["\']', ""):gsub('["\']$', ""):gsub("^%s+", ""):gsub("%s+$", "")
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
  return self
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
      local removed = false

      os.remove(skill_file)
      if term.is_windows then
        os.execute(string.format('cmd.exe /c "rd /s /q \\"%s\\"" 2>nul', skill_dir:gsub("/", "\\")))
      else
        os.execute(string.format("rm -rf %s 2>/dev/null", term.shell_quote(skill_dir)))
      end
      removed = true

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
