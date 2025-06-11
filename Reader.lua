-- Reader.lua
-- high performance, safe, and feature-rich binary reader in Lua

local bit32 = bit32 or require("bit32")

local Reader = {}
Reader.__index = Reader

local defaultFloatPrecision = 24

local function assertBounds(cursor, size, length)
    if cursor + size > length then
        error(("Attempt to read %d bytes beyond stream length %d at position %d"):format(size, length, cursor))
    end
end

-- To reduce overhead of multiple function calls for nextByte etc,
-- implement batch read where applicable

function Reader.new(bytecode)
    local stream = buffer.fromstring(bytecode)
    local length = buffer.len(stream)
    local cursor = 0
    local FLOAT_PRECISION = defaultFloatPrecision

    local self = setmetatable({}, Reader)

    -- Cache local references for speed
    local _assertBounds = assertBounds
    local _stream = stream
    local _length = length

    -- Helpers to read unsigned/signed integers more efficiently
    -- Without calling nextByte repeatedly in higher level functions

    -- Basic byte reading
    function self:len() return _length end
    function self:remaining() return _length - cursor end
    function self:getPosition() return cursor end

    function self:setPosition(pos)
        assert(type(pos) == "number" and pos >= 0 and pos <= _length, "Invalid cursor position")
        cursor = pos
    end

    -- Peek without advance
    function self:peekByte()
        _assertBounds(cursor, 1, _length)
        return buffer.readu8(_stream, cursor)
    end

    -- Next unsigned byte, move cursor
    function self:nextByte()
        _assertBounds(cursor, 1, _length)
        local b = buffer.readu8(_stream, cursor)
        cursor = cursor + 1
        return b
    end

    -- Next signed byte, move cursor
    function self:nextSignedByte()
        _assertBounds(cursor, 1, _length)
        local b = buffer.readi8(_stream, cursor)
        cursor = cursor + 1
        return b
    end

    -- Read N bytes as array without per-byte overhead
    function self:nextBytes(count)
        _assertBounds(cursor, count, _length)
        local bytes = {}
        local c = cursor
        for i = 1, count do
            bytes[i] = buffer.readu8(_stream, c)
            c = c + 1
        end
        cursor = cursor + count
        return bytes
    end

    function self:nextChar()
        return string.char(self:nextByte())
    end

    -- Read little-endian unsigned 16-bit (2 bytes)
    function self:nextUInt16()
        _assertBounds(cursor, 2, _length)
        local b1 = buffer.readu8(_stream, cursor)
        local b2 = buffer.readu8(_stream, cursor + 1)
        cursor = cursor + 2
        return b1 + b2 * 256
    end

    -- Read signed 16-bit little endian
    function self:nextInt16()
        local val = self:nextUInt16()
        if val >= 0x8000 then
            val = val - 0x10000
        end
        return val
    end

    -- Read little-endian unsigned 32-bit (4 bytes)
    function self:nextUInt32()
        _assertBounds(cursor, 4, _length)
        local b1 = buffer.readu8(_stream, cursor)
        local b2 = buffer.readu8(_stream, cursor + 1)
        local b3 = buffer.readu8(_stream, cursor + 2)
        local b4 = buffer.readu8(_stream, cursor + 3)
        cursor = cursor + 4
        return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end

    function self:nextInt32()
        local val = self:nextUInt32()
        if val >= 0x80000000 then
            val = val - 0x100000000
        end
        return val
    end

    -- Float and Double reading using buffer functions
    function self:nextFloat()
        _assertBounds(cursor, 4, _length)
        local f = buffer.readf32(_stream, cursor)
        cursor = cursor + 4
        return tonumber(string.format("%." .. FLOAT_PRECISION .. "f", f))
    end

    function self:nextDouble()
        _assertBounds(cursor, 8, _length)
        local d = buffer.readf64(_stream, cursor)
        cursor = cursor + 8
        return d
    end

    -- VarInt reading up to 5 bytes (7 bits each + 1 bit continuation)
    function self:nextVarInt()
        local result = 0
        for i = 0, 4 do
            local b = self:nextByte()
            result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), i * 7))
            if not bit32.btest(b, 0x80) then
                return result
            end
        end
        error("VarInt too big or malformed!")
    end

    -- Read string of known length or with VarInt length
    function self:nextString(len)
        if not len then
            len = self:nextVarInt()
        end
        if len == 0 then
            return ""
        end
        _assertBounds(cursor, len, _length)
        local str = buffer.readstring(_stream, cursor, len)
        cursor = cursor + len
        return str
    end

    -- Read boolean (byte != 0)
    function self:nextBool()
        return self:nextByte() ~= 0
    end

    -- Read bits from one byte as boolean array
    function self:nextBits(count)
        count = count or 8
        local byte = self:nextByte()
        local bits = {}
        for i = 0, count - 1 do
            bits[i + 1] = bit32.band(bit32.rshift(byte, i), 1) == 1
        end
        return bits
    end

    -- Rewind cursor safely (default 1 byte)
    function self:rewind(steps)
        steps = steps or 1
        cursor = math.max(0, cursor - steps)
    end

    -- Set float precision formatting
    function self:setFloatPrecision(precision)
        assert(type(precision) == "number" and precision > 0 and precision <= 64, "Invalid float precision")
        FLOAT_PRECISION = precision
    end

    return self
end

-- Set global default float precision for all new readers
function Reader.setGlobalFloatPrecision(precision)
    assert(type(precision) == "number" and precision > 0 and precision <= 64, "Invalid float precision")
    defaultFloatPrecision = precision
end

return Reader
