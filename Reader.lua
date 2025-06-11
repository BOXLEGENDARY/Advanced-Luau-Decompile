-- reader
-- performance
local FLOAT_PRECISION = 24

local Reader = {}

function Reader.new(bytecode)
  local stream = buffer.fromstring(bytecode)
  local cursor = 0

  -- Localized buffer functions for performance
  local buflen = buffer.len
  local readu8 = buffer.readu8
  local readi8 = buffer.readi8
  local readu32 = buffer.readu32
  local readi32 = buffer.readi32
  local readf32 = buffer.readf32
  local readf64 = buffer.readf64
  local readstr = buffer.readstring
  local band = bit32.band
  local bor = bit32.bor
  local lshift = bit32.lshift
  local btest = bit32.btest
  local char = string.char
  local fmt = string.format
  local sub = string.sub

  local self = {}

  function self:len()
    return buflen(stream)
  end

  function self:nextByte()
    local result = readu8(stream, cursor)
    cursor = cursor + 1
    return result
  end

  function self:nextSignedByte()
    local result = readi8(stream, cursor)
    cursor = cursor + 1
    return result
  end

  function self:nextBytes(count)
    local result = {}
    for i = 1, count do
      result[i] = readu8(stream, cursor)
      cursor = cursor + 1
    end
    return result
  end

  function self:nextChar()
    return char(readu8(stream, cursor)); cursor = cursor + 1
  end

  function self:nextUInt32()
    local result = readu32(stream, cursor)
    cursor = cursor + 4
    return result
  end

  function self:nextInt32()
    local result = readi32(stream, cursor)
    cursor = cursor + 4
    return result
  end

  function self:nextFloat()
    local result = readf32(stream, cursor)
    cursor = cursor + 4
    -- Faster float precision limiter
    local s = fmt("%.30f", result)
    return tonumber(sub(s, 1, 2 + FLOAT_PRECISION)) -- "0." + precision
  end

  function self:nextVarInt()
    local result = 0
    for i = 0, 4 do
      local b = readu8(stream, cursor)
      cursor = cursor + 1
      result = bor(result, lshift(band(b, 0x7F), i * 7))
      if not btest(b, 0x80) then
        break
      end
    end
    return result
  end

  function self:nextString(len)
    len = len or self:nextVarInt()
    if len == 0 then
      return ""
    else
      local result = readstr(stream, cursor, len)
      cursor = cursor + len
      return result
    end
  end

  function self:nextDouble()
    local result = readf64(stream, cursor)
    cursor = cursor + 8
    return result
  end

  return self
end

function Reader:Set(...)
  FLOAT_PRECISION = ...
end

return Reader
