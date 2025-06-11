-- Readler.lua
-- performance
local FLOAT_PRECISION = 24

local Reader = {}

-- Constant for VarInt max bytes (as per Luau specification, usually 5 bytes for 32-bit uint)
local MAX_VARINT_BYTES = 5
-- Max length for strings to prevent excessive memory allocation/reading
local MAX_STRING_LENGTH = 1024 * 1024 * 10 -- 10 MB limit for strings, adjust as needed

function Reader.new(bytecode)
    -- Ensure bytecode is a string or a buffer. If it's a string, convert it to a buffer.
    local stream
    if type(bytecode) == "string" then
        stream = buffer.fromstring(bytecode)
    elseif typeof(bytecode) == "buffer" then -- Assuming 'typeof' is available to check for buffer type
        stream = bytecode
    else
        error("Invalid bytecode type provided. Must be a string or a buffer.")
    end

    local cursor = 0
    local len = buffer.len(stream) -- Pre-calculate length for efficiency

    local self = {}

    function self:len()
        return len
    end

    function self:getCursor()
        return cursor
    end

    function self:isEOF()
        return cursor >= len
    end

    -- Helper to check if enough bytes are available before reading
    local function checkBytes(count)
        if cursor + count > len then
            error(string.format("Attempt to read past end of buffer. Required: %d bytes, Available from cursor: %d bytes.", count, len - cursor))
        end
    end

    function self:nextByte()
        checkBytes(1)
        local result = buffer.readu8(stream, cursor)
        cursor += 1
        return result
    end

    function self:nextSignedByte()
        checkBytes(1)
        local result = buffer.readi8(stream, cursor)
        cursor += 1
        return result
    end

    function self:nextBytes(count)
        checkBytes(count)
        local result = {}
        for i = 1, count do
            -- Calling self:nextByte() directly will handle the cursor increment and internal bounds check
            table.insert(result, self:nextByte())
        end
        return result
    end

    function self:nextChar()
        return string.char(self:nextByte())
    end

    function self:nextUInt32()
        checkBytes(4)
        local result = buffer.readu32(stream, cursor)
        cursor += 4
        return result
    end

    function self:nextInt32()
        checkBytes(4)
        local result = buffer.readi32(stream, cursor)
        cursor += 4
        return result
    end

    function self:nextFloat()
        checkBytes(4)
        local result = buffer.readf32(stream, cursor)
        cursor += 4
        -- Using string.format for float precision can be slow. Consider if absolutely necessary.
        -- If not, just return 'result' directly.
        return tonumber(string.format(`%0.{FLOAT_PRECISION}f`, result))
    end

    function self:nextVarInt()
        local result = 0
        for i = 0, MAX_VARINT_BYTES - 1 do -- Limit to 5 bytes for 32-bit VarInt
            checkBytes(1) -- Check before reading each byte
            local b = self:nextByte()
            result = bit32.bor(result, bit32.lshift(bit32.band(b, 0x7F), i * 7))

            if bit32.band(b, 0x80) == 0 then -- Check for the continuation bit
                return result
            end
        end
        -- If we reach here, it means the VarInt did not terminate within MAX_VARINT_BYTES
        error("Malformed VarInt: Did not terminate within " .. MAX_VARINT_BYTES .. " bytes.")
    end

    function self:nextString()
        local len = self:nextVarInt() -- Read length as VarInt

        if len > MAX_STRING_LENGTH then
            error(string.format("String length (%d) exceeds maximum allowed (%d). Possible malformed bytecode.", len, MAX_STRING_LENGTH))
        end

        checkBytes(len) -- Check if the entire string can be read

        -- For Luau, strings are usually stored as raw bytes.
        -- We read them as a raw byte sequence and convert to string.
        local start_cursor = cursor
        cursor += len
        -- This part might need adjustment based on how 'buffer' API provides substring
        -- Assuming 'buffer.tostring' can convert a sub-section of a buffer.
        -- If not, you might need to read byte by byte and concatenate, which is slower.
        return buffer.tostring(stream, start_cursor, len)
    end

    -- NOTE: This Readerua only provides basic read functions.
    -- A full decompiler would then use these functions to read the more complex
    -- structures defined in Luau.txt (e.g., protos, functions, constants, etc.).
    -- Example (conceptual, not part of Reader.txt):
    -- function readProto(reader)
    --     local proto = {}
    --     proto.tag = reader:nextByte()
    --     proto.constants_count = reader:nextVarInt()
    --     proto.constants = {}
    --     for i=1, proto.constants_count do
    --         table.insert(proto.constants, readConstant(reader))
    --     end
    --     -- ... continue reading other fields like bytecode, upvalues, nested protos
    --     return proto
    -- end

    return self
end

return Reader
