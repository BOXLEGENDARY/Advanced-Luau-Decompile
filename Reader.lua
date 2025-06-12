-- Reader
-- High Performance
local FLOAT_PRECISION = 24

local Reader = {}

function Reader.new(bytecode)
    local stream = buffer.fromstring(bytecode)
    local cursor = 0

    local self = {}

    local string_char = string.char
    local format = string.format
    local tonumber = tonumber
    local bor = bit32.bor
    local band = bit32.band
    local lshift = bit32.lshift
    local btest = bit32.btest
    local insert = table.insert

    function self:len()
        return buffer.len(stream)
    end

    function self:checkBounds(size, funcName)
        if cursor + size > self:len() then
            print(("Warning: Out of bounds read in %s at position %d (need %d bytes, but length is %d)"):format(
                funcName, cursor, size, self:len()
            ))
        end
    end

    function self:nextByte()
        self:checkBounds(1, "nextByte")
        local result = buffer.readu8(stream, cursor)
        cursor = cursor + 1
        return result
    end

    function self:nextSignedByte()
        self:checkBounds(1, "nextSignedByte")
        local result = buffer.readi8(stream, cursor)
        cursor = cursor + 1
        return result
    end

    function self:nextBytes(count)
        self:checkBounds(count, "nextBytes")
        local result = table.create(count)
        for i = 1, count do
            result[i] = self:nextByte()
        end
        return result
    end

    function self:nextChar()
        local byte = self:nextByte()
        return string_char(byte)
    end

    function self:nextUInt32()
        self:checkBounds(4, "nextUInt32")
        local result = buffer.readu32(stream, cursor)
        cursor = cursor + 4
        return result
    end

    function self:nextInt32()
        self:checkBounds(4, "nextInt32")
        local result = buffer.readi32(stream, cursor)
        cursor = cursor + 4
        return result
    end

    function self:nextFloat()
        self:checkBounds(4, "nextFloat")
        local result = buffer.readf32(stream, cursor)
        cursor = cursor + 4
        return tonumber(format(`%0.${FLOAT_PRECISION}f`, result))
    end

    function self:nextVarInt()
        local result = 0
        for i = 0, 4 do
            local b = self:nextByte()
            result = bor(result, lshift(band(b, 0x7F), i * 7))
            if not btest(b, 0x80) then
                break
            end
        end
        return result
    end

    function self:nextString(len)
        if not len then
            len = self:nextVarInt()
        end
        if len == 0 then
            return ""
        else
            self:checkBounds(len, "nextString")
            local result = buffer.readstring(stream, cursor, len)
            cursor = cursor + len
            return result
        end
    end

    function self:nextDouble()
        self:checkBounds(8, "nextDouble")
        local result = buffer.readf64(stream, cursor)
        cursor = cursor + 8
        return result
    end

    return self
end

function Reader:Set(precision)
    FLOAT_PRECISION = precision
end

return Reader
