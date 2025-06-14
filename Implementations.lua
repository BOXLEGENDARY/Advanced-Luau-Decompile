local _ENV = (getgenv or getfenv)()

-- Dependencies (local fast-access references)
local string_find    = string.find
local string_match   = string.match
local string_rep     = string.rep
local string_char    = string.char
local string_format  = string.format
local tostring       = tostring
local type           = type
local rawget         = rawget
local math_max       = math.max

-- Module table
local Implementations = {}

-- Converts number to boolean (0 = false, non-zero = true)
local function toBoolean(n)
    return n ~= 0
end

-- Escapes and quotes string safely
local function toEscapedString(s)
    if type(s) ~= "string" then
        return tostring(s)
    end

    local hasQuote     = string_find(s, '"', 1, true)
    local hasApostrophe = string_find(s, "'", 1, true)

    if hasQuote and hasApostrophe then
        return "[[" .. s .. "]]"
    elseif hasQuote then
        return "'" .. s .. "'"
    else
        return '"' .. s .. '"'
    end
end

-- Format a table index as valid Lua code (dot-style or bracket-style)
local function formatIndexString(s)
    if type(s) == "string" then
        if string_match(s, "^[%a_][%w_]*$") then
            return "." .. s
        else
            return "[" .. toEscapedString(s) .. "]"
        end
    end
    return tostring(s)
end

-- Pads a string on the left with a given character
local function padLeft(x, char, len)
    local str = tostring(x)
    local pad = math_max(0, len - #str)
    return string_rep(char, pad) .. str
end

-- Pads a string on the right with a given character
local function padRight(x, char, len)
    local str = tostring(x)
    local pad = math_max(0, len - #str)
    return str .. string_rep(char, pad)
end

-- Check if variable exists in global _ENV
local function isGlobal(s)
    return rawget(_ENV, s) ~= nil
end

-- Export functions to module table
Implementations.toBoolean         = toBoolean
Implementations.toEscapedString   = toEscapedString
Implementations.formatIndexString = formatIndexString
Implementations.padLeft           = padLeft
Implementations.padRight          = padRight
Implementations.isGlobal          = isGlobal

return Implementations
