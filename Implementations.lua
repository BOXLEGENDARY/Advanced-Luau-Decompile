local _ENV = (getgenv and getgenv()) or (getfenv and getfenv(1)) or _ENV

local Implementations = {}

local string_find = string.find
local string_match = string.match
local string_rep = string.rep
local tostring = tostring
local type = type
local rawget = rawget
local math_max = math.max

-- from number to boolean
local function toBoolean(n)
  return n ~= 0
end

-- Auto escape string
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

-- picks indexing method based on characters in a string
local function formatIndexString(s)
  if type(s) == "string" then
    if string_match(s, "^[%a_][%w_]*$") then
      return "." .. s
    end
    return "[" .. toEscapedString(s) .. "]"
  end
  return tostring(s)
end

-- Pad string to the left
local function padLeft(text, paddingChar, targetLen)
  local str = tostring(text)
  local pad = math_max(0, targetLen - #str)
  return string_rep(paddingChar, pad) .. str
end

-- Pad string to the right
local function padRight(text, paddingChar, targetLen)
  local str = tostring(text)
  local pad = math_max(0, targetLen - #str)
  return str .. string_rep(paddingChar, pad)
end

-- returns true if passed string is a key pointing to a Roblox global
local function isGlobal(s)
  return rawget(_ENV, s) ~= nil
end

-- Export implementations
Implementations.toBoolean = toBoolean
Implementations.toEscapedString = toEscapedString
Implementations.formatIndexString = formatIndexString
Implementations.padLeft = padLeft
Implementations.padRight = padRight
Implementations.isGlobal = isGlobal

return Implementations