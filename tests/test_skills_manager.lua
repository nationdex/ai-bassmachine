package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("loader")

local SkillManager = require("ai-bassmachine.skills.manager")

-- Test isolated temporary directories
local tmp_agents = "/tmp/test_skills_agents"
local tmp_claude = "/tmp/test_skills_claude"
local tmp_opencode = "/tmp/test_skills_opencode"

os.execute("rm -rf " .. tmp_agents .. " " .. tmp_claude .. " " .. tmp_opencode)

local skill_mgr = SkillManager.new()
skill_mgr.targets = {
  { id = "agents", name = "Agents Test", dir = tmp_agents },
  { id = "claude", name = "Claude Test", dir = tmp_claude },
  { id = "opencode", name = "OpenCode Test", dir = tmp_opencode },
}

-- 1. Install skill to single target
local sample_skill = [[---
name: code-reviewer
description: Fast surgical code reviewer with zero fluff.
---

# Code Reviewer
Inspect diffs and identify issues.
]]

local res_single = skill_mgr:install_skill("code-reviewer", sample_skill, "agents")
assert(#res_single == 1, "expected 1 target result")
assert(res_single[1].success == true, "failed to install skill to agents")

-- 2. Verify list_all dynamically discovers it
local all_1 = skill_mgr:list_all()
assert(#all_1 == 1, "expected 1 skill found")
assert(all_1[1].name == "code-reviewer", "skill name mismatch")
assert(#all_1[1].installed_in == 1 and all_1[1].installed_in[1] == "agents", "target mismatch")

-- 3. Broadcast / sync skill across all targets
local ok_sync, res_sync = skill_mgr:sync_skill_to_all("code-reviewer")
assert(ok_sync == true, "expected sync_skill_to_all to succeed")
assert(#res_sync == 3, "expected broadcast to all 3 targets")

local all_2 = skill_mgr:list_all()
assert(#all_2 == 1, "still 1 distinct skill")
assert(#all_2[1].installed_in == 3, "expected skill installed in all 3 targets")

-- 4. Install another skill to all
local res_all = skill_mgr:install_skill("test-runner", "# Test Runner\nRun tests\n", "all")
assert(#res_all == 3, "expected 3 results for test-runner")

local all_3 = skill_mgr:list_all()
assert(#all_3 == 2, "expected 2 skills total")

-- 5. Remove skill from one target, then all
skill_mgr:remove_skill("test-runner", "claude")
local all_4 = skill_mgr:list_all()
for _, sk in ipairs(all_4) do
  if sk.name == "test-runner" then
    assert(#sk.installed_in == 2, "expected test-runner in 2 targets after removing from claude")
  end
end

skill_mgr:remove_skill("test-runner", "all")
local all_5 = skill_mgr:list_all()
assert(#all_5 == 1, "expected only code-reviewer remaining")

-- 6. Skills Marketplace dynamic discovery
local market_skills = skill_mgr:get_marketplace_skills()
assert(#market_skills > 0, "expected online skills in marketplace")
local sample_market_skill = market_skills[1]
assert(sample_market_skill.name ~= nil, "missing name in market skill")
assert(sample_market_skill.raw_url ~= nil, "missing raw_url in market skill")

-- Cleanup
os.execute("rm -rf " .. tmp_agents .. " " .. tmp_claude .. " " .. tmp_opencode)

io.write("PASS: tests/test_skills_manager.lua\n")
