local FLOAT_PRECISION = 24

local Reader = {}

function Reader.new(bytecode)
    local stream = buffer.fromstring(bytecode)
    local length = buffer.len(stream)
    local cursor = 0

    local bor = bit32.bor
    local band = bit32.band
    local lshift = bit32.lshift
    local btest = bit32.btest

    local self = {}

    function self:len()
        return length
    end

    local function checkBounds(n)
        if cursor + n > length then
            error(string.format("Read %d bytes at position %d exceeds buffer length %d", n, cursor, length))
        end
    end

    function self:nextByte()
        checkBounds(1)
        local result = buffer.readu8(stream, cursor)
        cursor = cursor + 1
        return result
    end

    function self:nextSignedByte()
        checkBounds(1)
        local result = buffer.readi8(stream, cursor)
        cursor = cursor + 1
        return result
    end

    function self:nextBytes(count)
        checkBounds(count)
        local result = table.create(count)
        for i = 1, count do
            result[i] = buffer.readu8(stream, cursor)
            cursor = cursor + 1
        end
        return result
    end

    function self:nextBlock(count)
        checkBounds(count)
        local result = buffer.readstring(stream, cursor, count)
        cursor = cursor + count
        return result
    end

    function self:nextChar()
        return string.char(self:nextByte())
    end

    function self:nextUInt32()
        checkBounds(4)
        local result = buffer.readu32(stream, cursor)
        cursor = cursor + 4
        return result
    end

    function self:nextInt32()
        checkBounds(4)
        local result = buffer.readi32(stream, cursor)
        cursor = cursor + 4
        return result
    end

    function self:nextFloat()
        checkBounds(4)
        local result = buffer.readf32(stream, cursor)
        cursor = cursor + 4
        return result
    end

    function self:nextDouble()
        checkBounds(8)
        local result = buffer.readf64(stream, cursor)
        cursor = cursor + 8
        return result
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
            return self:nextBlock(len)
        end
    end

    return self
end

function Reader:Set(precision)
    FLOAT_PRECISION = precision
end

return Reader
