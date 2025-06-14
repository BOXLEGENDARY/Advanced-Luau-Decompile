local _ENV = (getgenv or getfenv)()

local Implementations = {}

local string_find = string.find
local string_match = string.match
local string_rep = string.rep
local string_char = string.char
local tostring = tostring
local type = type
local rawget = rawget
local math_max = math.max
local string_format = string.format

-- from number to boolean
local function toBoolean(n)
  return n ~= 0
end

-- auto escape string
local function toEscapedString(s)
  if type(s) == "string" then
    local hasQuote = string_find(s, '"', 1, true)
    local hasApostrophe = string_find(s, "'", 1, true)

    if hasQuote and hasApostrophe then
      return "[[" .. s .. "]]"
    elseif hasQuote then
      return "'" .. s .. "'"
    end
    return '"' .. s .. '"'
  end
  return tostring(s)
end

-- pick index format
local function formatIndexString(s)
  if type(s) == "string" then
    if string_match(s, "^[%a_][%w_]*$") then
      return "." .. s
    end
    return "[" .. toEscapedString(s) .. "]"
  end
  return tostring(s)
end

-- safe padLeft
local function padLeft(x, char, len)
  local str = tostring(x)
  local pad = math_max(0, len - #str)
  return string_rep(char, pad) .. str
end

-- safe padRight
local function padRight(x, char, len)
  local str = tostring(x)
  local pad = math_max(0, len - #str)
  return str .. string_rep(char, pad)
end

-- check _ENV global safely
local function isGlobal(s)
  return rawget(_ENV, s) ~= nil
end

-- Assign all to table (no metatable, fast lookup)
Implementations.toBoolean = toBoolean
Implementations.toEscapedString = toEscapedString
Implementations.formatIndexString = formatIndexString
Implementations.padLeft = padLeft
Implementations.padRight = padRight
Implementations.isGlobal = isGlobal

return Implementations