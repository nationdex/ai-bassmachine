-- MCP Bass Machine - Pure Lua TOML Parser & Serializer
-- Handles nested tables, arrays, strings, numbers, booleans, and formats cleanly.

local toml = {}

local function trim(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function parse_literal(val_str)
  val_str = trim(val_str)
  if val_str == "true" then
    return true
  elseif val_str == "false" then
    return false
  end

  -- String with double quotes
  if val_str:sub(1, 1) == '"' and val_str:sub(-1) == '"' and #val_str >= 2 then
    local inner = val_str:sub(2, -2)
    inner = inner:gsub('\\"', '"'):gsub("\\n", "\n"):gsub("\\t", "\t"):gsub("\\\\", "\\")
    return inner
  end

  -- String with single quotes (literal string)
  if val_str:sub(1, 1) == "'" and val_str:sub(-1) == "'" and #val_str >= 2 then
    return val_str:sub(2, -2)
  end

  -- Array
  if val_str:sub(1, 1) == "[" and val_str:sub(-1) == "]" then
    local inner = trim(val_str:sub(2, -2))
    if inner == "" then
      return {}
    end
    local list = {}
    local item = ""
    local in_quotes = false
    local depth = 0
    for i = 1, #inner do
      local ch = inner:sub(i, i)
      if ch == '"' and inner:sub(i - 1, i - 1) ~= "\\" then
        in_quotes = not in_quotes
        item = item .. ch
      elseif not in_quotes and ch == "[" then
        depth = depth + 1
        item = item .. ch
      elseif not in_quotes and ch == "]" then
        depth = depth - 1
        item = item .. ch
      elseif not in_quotes and depth == 0 and ch == "," then
        table.insert(list, parse_literal(item))
        item = ""
      else
        item = item .. ch
      end
    end
    if trim(item) ~= "" then
      table.insert(list, parse_literal(item))
    end
    return list
  end

  -- Number
  local num = tonumber(val_str)
  if num ~= nil then
    return num
  end

  -- Default to unquoted string if non-empty
  return val_str
end

function toml.parse(text)
  if not text then
    return {}
  end
  local root = {}
  local current_section = root

  local lines = {}
  for line in text:gmatch("([^\r\n]*)\r?\n?") do
    table.insert(lines, line)
  end

  for _, raw_line in ipairs(lines) do
    local line = trim(raw_line)
    if line ~= "" and line:sub(1, 1) ~= "#" then
      -- Section header: [section] or [section.sub]
      if line:sub(1, 1) == "[" and line:sub(-1) == "]" then
        local header = line:sub(2, -2)
        local parts = {}
        for part in header:gmatch("[^%.]+") do
          table.insert(parts, trim(part))
        end

        current_section = root
        for _, part in ipairs(parts) do
          if not current_section[part] or type(current_section[part]) ~= "table" then
            current_section[part] = {}
          end
          current_section = current_section[part]
        end
      else
        -- Key-value pair: key = value
        local eq_pos = line:find("=")
        if eq_pos then
          local key = trim(line:sub(1, eq_pos - 1))
          local rest = trim(line:sub(eq_pos + 1))
          -- Remove trailing inline comment if not inside string
          local in_str = false
          local cut_idx = #rest
          for i = 1, #rest do
            local c = rest:sub(i, i)
            if c == '"' and (i == 1 or rest:sub(i - 1, i - 1) ~= "\\") then
              in_str = not in_str
            elseif not in_str and c == "#" then
              cut_idx = i - 1
              break
            end
          end
          local val_str = trim(rest:sub(1, cut_idx))
          current_section[key] = parse_literal(val_str)
        end
      end
    end
  end

  return root
end

local function format_val(val)
  local t = type(val)
  if t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    return tostring(val)
  elseif t == "string" then
    local esc = val:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t")
    return '"' .. esc .. '"'
  elseif t == "table" then
    local parts = {}
    for idx = 1, #val do
      table.insert(parts, format_val(val[idx]))
    end
    return "[" .. table.concat(parts, ", ") .. "]"
  end
  return '""'
end

function toml.encode(tbl, indent)
  indent = indent or ""
  local out = {}

  -- First output primitive values at current level
  local keys = {}
  for k in pairs(tbl) do
    table.insert(keys, k)
  end
  table.sort(keys)

  local sub_tables = {}
  for _, k in ipairs(keys) do
    local v = tbl[k]
    if type(v) == "table" and #v == 0 and next(v) ~= nil then
      table.insert(sub_tables, k)
    else
      table.insert(out, string.format("%s = %s", k, format_val(v)))
    end
  end

  -- Then sub-tables
  for _, sub_name in ipairs(sub_tables) do
    local prefix = (indent == "" and sub_name or (indent .. "." .. sub_name))
    table.insert(out, "")
    table.insert(out, "[" .. prefix .. "]")
    local sub_keys = {}
    for sk in pairs(tbl[sub_name]) do
      table.insert(sub_keys, sk)
    end
    table.sort(sub_keys)

    for _, sk in ipairs(sub_keys) do
      local sv = tbl[sub_name][sk]
      if type(sv) == "table" and #sv == 0 and next(sv) ~= nil then
        table.insert(out, "")
        table.insert(out, "[" .. prefix .. "." .. sk .. "]")
        local nested_keys = {}
        for nk in pairs(sv) do
          table.insert(nested_keys, nk)
        end
        table.sort(nested_keys)
        for _, nk in ipairs(nested_keys) do
          table.insert(out, string.format("%s = %s", nk, format_val(sv[nk])))
        end
      else
        table.insert(out, string.format("%s = %s", sk, format_val(sv)))
      end
    end
  end

  return table.concat(out, "\n") .. "\n"
end

return toml
