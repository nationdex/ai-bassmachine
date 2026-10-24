-- MCP Bass Machine - Ephemeral History Manager
-- Tracks MCP sessions without permanent installation. Cleanable on-demand or automatically.

local json = require("mcp-bassmachine.utils.json")

local HistoryManager = {}
HistoryManager.__index = HistoryManager

function HistoryManager.new(history_file, auto_clean, max_entries, retention_hours)
  local self = setmetatable({}, HistoryManager)
  self.filepath = history_file or ".bassmachine_history.json"
  self.auto_clean = (auto_clean ~= false)
  self.max_entries = max_entries or 50
  self.retention_hours = retention_hours or 24
  self.entries = {}
  self:load()
  if self.auto_clean then
    self:run_auto_cleanup()
  end
  return self
end

function HistoryManager:load()
  local f = io.open(self.filepath, "r")
  if not f then
    self.entries = {}
    return
  end
  local content = f:read("*a")
  f:close()

  local decoded = json.decode(content)
  if decoded and type(decoded) == "table" then
    self.entries = decoded
  else
    self.entries = {}
  end
end

function HistoryManager:save()
  local f = io.open(self.filepath, "w")
  if not f then
    return false, "Could not open history file for writing"
  end
  f:write(json.encode(self.entries))
  f:close()
  return true
end

function HistoryManager:add(record)
  record.id = record.id or tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  record.timestamp = record.timestamp or os.time()
  record.time_formatted = os.date("%Y-%m-%d %H:%M:%S", record.timestamp)

  table.insert(self.entries, 1, record) -- Newest first

  if self.auto_clean then
    self:run_auto_cleanup()
  else
    self:save()
  end
  return record
end

function HistoryManager:list()
  return self.entries
end

function HistoryManager:count()
  return #self.entries
end

function HistoryManager:clean_all()
  self.entries = {}
  self:save()
  return true
end

function HistoryManager:clean_stale(hours)
  hours = hours or self.retention_hours
  local cutoff = os.time() - (hours * 3600)
  local filtered = {}
  for _, item in ipairs(self.entries) do
    if item.timestamp and item.timestamp >= cutoff then
      table.insert(filtered, item)
    end
  end
  self.entries = filtered
  self:save()
  return true
end

function HistoryManager:run_auto_cleanup()
  -- 1. Remove expired
  self:clean_stale(self.retention_hours)

  -- 2. Cap at max entries
  if #self.entries > self.max_entries then
    local trimmed = {}
    for i = 1, self.max_entries do
      table.insert(trimmed, self.entries[i])
    end
    self.entries = trimmed
  end
  self:save()
end

return HistoryManager
