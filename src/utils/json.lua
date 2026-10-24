-- MCP Bass Machine - Pure Lua JSON Parser & Serializer
-- Compatible with Lua 5.1, 5.2, 5.3, 5.4, and LuaJIT.

local json = {}

local function kind_of(obj)
  if type(obj) ~= "table" then
    return type(obj)
  end
  local i = 1
  for _ in pairs(obj) do
    if obj[i] ~= nil then
      i = i + 1
    else
      return "table"
    end
  end
  if i == 1 then
    return "empty_table"
  else
    return "array"
  end
end

local escape_char_map = {
  ["\\"] = "\\\\",
  ['"'] = '\\"',
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

local function escape_str(s)
  return (
    s:gsub('["\\\b\f\n\r\t]', escape_char_map):gsub("[%z\1-\31]", function(c)
      return string.format("\\u%04x", string.byte(c))
    end)
  )
end

function json.encode(val)
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    if val ~= val then
      return "null" -- NaN
    elseif val >= math.huge or val <= -math.huge then
      return "null" -- Inf
    end
    return tostring(val)
  elseif t == "string" then
    return '"' .. escape_str(val) .. '"'
  elseif t == "table" then
    local k = kind_of(val)
    if k == "array" then
      local parts = {}
      for idx = 1, #val do
        parts[idx] = json.encode(val[idx])
      end
      return "[" .. table.concat(parts, ",") .. "]"
    elseif k == "empty_table" then
      return "{}"
    else
      local parts = {}
      for key, v in pairs(val) do
        if type(key) == "string" or type(key) == "number" then
          table.insert(parts, '"' .. escape_str(tostring(key)) .. '":' .. json.encode(v))
        end
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  end
  return "null"
end

local function skip_whitespace(str, pos)
  return str:find("%S", pos) or (#str + 1)
end

local parse_value

local function parse_string(str, pos)
  local len = #str
  local res = {}
  pos = pos + 1 -- skip opening quote
  while pos <= len do
    local c = str:sub(pos, pos)
    if c == '"' then
      return table.concat(res), pos + 1
    elseif c == "\\" then
      local next_c = str:sub(pos + 1, pos + 1)
      if next_c == '"' or next_c == "\\" or next_c == "/" then
        table.insert(res, next_c)
        pos = pos + 2
      elseif next_c == "b" then
        table.insert(res, "\b")
        pos = pos + 2
      elseif next_c == "f" then
        table.insert(res, "\f")
        pos = pos + 2
      elseif next_c == "n" then
        table.insert(res, "\n")
        pos = pos + 2
      elseif next_c == "r" then
        table.insert(res, "\r")
        pos = pos + 2
      elseif next_c == "t" then
        table.insert(res, "\t")
        pos = pos + 2
      elseif next_c == "u" then
        local hex = str:sub(pos + 2, pos + 5)
        local code = tonumber(hex, 16)
        if code then
          if code < 128 then
            table.insert(res, string.char(code))
          elseif code < 2048 then
            table.insert(res, string.char(192 + math.floor(code / 64), 128 + (code % 64)))
          else
            table.insert(
              res,
              string.char(224 + math.floor(code / 4096), 128 + (math.floor(code / 64) % 64), 128 + (code % 64))
            )
          end
        end
        pos = pos + 6
      else
        table.insert(res, next_c)
        pos = pos + 2
      end
    else
      table.insert(res, c)
      pos = pos + 1
    end
  end
  return nil, pos, "Unterminated string"
end

local function parse_number(str, pos)
  local m_start, m_end = str:find("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
  if m_start then
    local num = tonumber(str:sub(m_start, m_end))
    return num, m_end + 1
  end
  return nil, pos, "Invalid number"
end

local function parse_array(str, pos)
  local arr = {}
  pos = pos + 1 -- skip '['
  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) == "]" then
    return arr, pos + 1
  end

  while pos <= #str do
    local val
    val, pos = parse_value(str, pos)
    table.insert(arr, val)
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "]" then
      return arr, pos + 1
    elseif c == "," then
      pos = pos + 1
      pos = skip_whitespace(str, pos)
    else
      return nil, pos, "Expected ',' or ']' in array"
    end
  end
  return nil, pos, "Unclosed array"
end

local function parse_object(str, pos)
  local obj = {}
  pos = pos + 1 -- skip '{'
  pos = skip_whitespace(str, pos)
  if str:sub(pos, pos) == "}" then
    return obj, pos + 1
  end

  while pos <= #str do
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= '"' then
      return nil, pos, "Expected string key in object"
    end
    local key
    key, pos = parse_string(str, pos)
    pos = skip_whitespace(str, pos)
    if str:sub(pos, pos) ~= ":" then
      return nil, pos, "Expected ':' after key in object"
    end
    pos = pos + 1 -- skip ':'
    local val
    val, pos = parse_value(str, pos)
    obj[key] = val
    pos = skip_whitespace(str, pos)
    local c = str:sub(pos, pos)
    if c == "}" then
      return obj, pos + 1
    elseif c == "," then
      pos = pos + 1
    else
      return nil, pos, "Expected ',' or '}' in object"
    end
  end
  return nil, pos, "Unclosed object"
end

function parse_value(str, pos)
  pos = skip_whitespace(str, pos)
  local c = str:sub(pos, pos)
  if c == '"' then
    return parse_string(str, pos)
  elseif c == "{" then
    return parse_object(str, pos)
  elseif c == "[" then
    return parse_array(str, pos)
  elseif c == "t" and str:sub(pos, pos + 3) == "true" then
    return true, pos + 4
  elseif c == "f" and str:sub(pos, pos + 4) == "false" then
    return false, pos + 5
  elseif c == "n" and str:sub(pos, pos + 3) == "null" then
    return nil, pos + 4
  elseif c == "-" or (c >= "0" and c <= "9") then
    return parse_number(str, pos)
  end
  return nil, pos, "Unexpected character: " .. tostring(c)
end

function json.decode(str)
  if type(str) ~= "string" or #str == 0 then
    return nil, "empty string"
  end
  local val, _, err = parse_value(str, 1)
  if err then
    return nil, err
  end
  return val
end

return json
