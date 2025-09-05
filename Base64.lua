--!native
--!optimize 2

local lookupValueToCharacter = buffer.create(64)
local lookupCharacterToValue = buffer.create(256)

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local padding = string.byte("=")

for i = 1, #alphabet do
	local value = i - 1
	local char = string.byte(alphabet, i)
	buffer.writeu8(lookupValueToCharacter, value, char)
	buffer.writeu8(lookupCharacterToValue, char, value)
end

local function encode(input: buffer): buffer
	local inputLength = buffer.len(input)
	if inputLength == 0 then return buffer.create(0) end

	local inputChunks = math.floor(inputLength / 3)
	local remainder = inputLength % 3
	local outputLength = inputChunks * 4 + (remainder > 0 and 4 or 0)
	local output = buffer.create(outputLength)

	for i = 0, inputChunks - 1 do
		local inputIndex = i * 3
		local outputIndex = i * 4

		local b1, b2, b3 = buffer.readu8(input, inputIndex), buffer.readu8(input, inputIndex + 1), buffer.readu8(input, inputIndex + 2)
		local chunk = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2, 8), b3)

		buffer.writeu8(output, outputIndex,     buffer.readu8(lookupValueToCharacter, bit32.rshift(chunk, 18)))
		buffer.writeu8(output, outputIndex + 1, buffer.readu8(lookupValueToCharacter, bit32.band(bit32.rshift(chunk, 12), 0x3F)))
		buffer.writeu8(output, outputIndex + 2, buffer.readu8(lookupValueToCharacter, bit32.band(bit32.rshift(chunk, 6), 0x3F)))
		buffer.writeu8(output, outputIndex + 3, buffer.readu8(lookupValueToCharacter, bit32.band(chunk, 0x3F)))
	end

	if remainder > 0 then
		local lastIndex = inputChunks * 3
		local b1 = buffer.readu8(input, lastIndex)
		local b2 = remainder == 2 and buffer.readu8(input, lastIndex + 1) or 0

		local chunk = bit32.bor(bit32.lshift(b1, 16), bit32.lshift(b2, 8))
		local outputIndex = inputChunks * 4

		buffer.writeu8(output, outputIndex,     buffer.readu8(lookupValueToCharacter, bit32.rshift(chunk, 18)))
		buffer.writeu8(output, outputIndex + 1, buffer.readu8(lookupValueToCharacter, bit32.band(bit32.rshift(chunk, 12), 0x3F)))

		if remainder == 2 then
			buffer.writeu8(output, outputIndex + 2, buffer.readu8(lookupValueToCharacter, bit32.band(bit32.rshift(chunk, 6), 0x3F)))
		else
			buffer.writeu8(output, outputIndex + 2, padding)
		end
		buffer.writeu8(output, outputIndex + 3, padding)
	end

	return output
end

local function decode(input: buffer): buffer
	local inputLength = buffer.len(input)
	if inputLength == 0 then return buffer.create(0) end

	local paddingCount = 0
	if inputLength >= 1 and buffer.readu8(input, inputLength - 1) == padding then paddingCount += 1 end
	if inputLength >= 2 and buffer.readu8(input, inputLength - 2) == padding then paddingCount += 1 end

	local inputChunks = math.floor(inputLength / 4)
	local outputLength = inputChunks * 3 - paddingCount
	local output = buffer.create(outputLength)

	for i = 0, inputChunks - 2 do
		local inputIndex = i * 4
		local outputIndex = i * 3

		local v1 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex))
		local v2 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 1))
		local v3 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 2))
		local v4 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, inputIndex + 3))

		local chunk = bit32.bor(bit32.lshift(v1, 18), bit32.lshift(v2, 12), bit32.lshift(v3, 6), v4)

		buffer.writeu8(output, outputIndex,     bit32.rshift(chunk, 16))
		buffer.writeu8(output, outputIndex + 1, bit32.band(bit32.rshift(chunk, 8), 0xFF))
		buffer.writeu8(output, outputIndex + 2, bit32.band(chunk, 0xFF))
	end

	local lastInputIndex = (inputChunks - 1) * 4
	local lastOutputIndex = (inputChunks - 1) * 3

	local v1 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex))
	local v2 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 1))
	local v3 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 2))
	local v4 = buffer.readu8(lookupCharacterToValue, buffer.readu8(input, lastInputIndex + 3))

	local chunk = bit32.bor(bit32.lshift(v1, 18), bit32.lshift(v2, 12), bit32.lshift(v3, 6), v4)

	if paddingCount <= 2 then
		buffer.writeu8(output, lastOutputIndex, bit32.rshift(chunk, 16))
		if paddingCount <= 1 then
			buffer.writeu8(output, lastOutputIndex + 1, bit32.band(bit32.rshift(chunk, 8), 0xFF))
			if paddingCount == 0 then
				buffer.writeu8(output, lastOutputIndex + 2, bit32.band(chunk, 0xFF))
			end
		end
	end

	return output
end

return {
	encode = encode,
	decode = decode,
}