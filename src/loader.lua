-- AI Bass Machine - Module Loader
-- Enables seamless require("ai-bassmachine.*") and require("mcp-bassmachine.*") across all Lua versions.

package.path = "src/?.lua;src/?/init.lua;" .. package.path

local searchers = package.searchers or package.loaders
if searchers then
  table.insert(searchers, 2, function(modname)
    local sub = modname:match("^ai%-bassmachine%.(.*)$") or modname:match("^mcp%-bassmachine%.(.*)$")
    if sub then
      local rel_path = "src/" .. sub:gsub("%.", "/") .. ".lua"
      local f = io.open(rel_path, "r")
      if f then
        f:close()
        return loadfile(rel_path)
      end
    end
  end)
end

return true
