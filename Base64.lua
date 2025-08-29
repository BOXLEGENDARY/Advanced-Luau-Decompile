--!native
--!optimize 2

-- i didn't test if it error good luck
local lookupValueToCharacter = buffer.create(64)
local lookupCharacterToValue = buffer.create(256)

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local padding = string.byte("=")

local band, bor, rshift, lshift, byteswap = bit32.band, bit32.bor, bit32.rshift, bit32.lshift, bit32.byteswap
local readu8, readu32, writeu8, buflen = buffer.readu8, buffer.readu32, buffer.writeu8, buffer.len

for i = 1, 64 do
	local v = i - 1
	local c = string.byte(alphabet, i)
	writeu8(lookupValueToCharacter, v, c)
	writeu8(lookupCharacterToValue, c, v)
end

local function encode(input: buffer): buffer
	local inputLength = buflen(input)
	if inputLength == 0 then
		return buffer.create(0)
	end

	local inputChunks = math.ceil(inputLength / 3)
	local outputLength = inputChunks * 4
	local output = buffer.create(outputLength)

	for chunkIndex = 1, inputChunks - 1 do
		local inPos, outPos = (chunkIndex - 1) * 3, (chunkIndex - 1) * 4
		local chunk = byteswap(readu32(input, inPos))

		local v1 = rshift(chunk, 26)
		local v2 = band(rshift(chunk, 20), 0x3F)
		local v3 = band(rshift(chunk, 14), 0x3F)
		local v4 = band(rshift(chunk, 8), 0x3F)

		writeu8(output, outPos,     readu8(lookupValueToCharacter, v1))
		writeu8(output, outPos + 1, readu8(lookupValueToCharacter, v2))
		writeu8(output, outPos + 2, readu8(lookupValueToCharacter, v3))
		writeu8(output, outPos + 3, readu8(lookupValueToCharacter, v4))
	end

	local remainder = inputLength % 3
	local outPos = outputLength - 4
	if remainder == 1 then
		local c = readu8(input, inputLength - 1)
		local v1, v2 = rshift(c, 2), band(lshift(c, 4), 0x3F)

		writeu8(output, outPos,     readu8(lookupValueToCharacter, v1))
		writeu8(output, outPos + 1, readu8(lookupValueToCharacter, v2))
		writeu8(output, outPos + 2, padding)
		writeu8(output, outPos + 3, padding)

	elseif remainder == 2 then
		local c = bor(lshift(readu8(input, inputLength - 2), 8), readu8(input, inputLength - 1))
		local v1, v2, v3 = rshift(c, 10), band(rshift(c, 4), 0x3F), band(lshift(c, 2), 0x3F)

		writeu8(output, outPos,     readu8(lookupValueToCharacter, v1))
		writeu8(output, outPos + 1, readu8(lookupValueToCharacter, v2))
		writeu8(output, outPos + 2, readu8(lookupValueToCharacter, v3))
		writeu8(output, outPos + 3, padding)

	else -- remainder == 0
		local c = bor(
			lshift(readu8(input, inputLength - 3), 16),
			lshift(readu8(input, inputLength - 2), 8),
			readu8(input, inputLength - 1)
		)

		local v1, v2, v3, v4 = rshift(c, 18), band(rshift(c, 12), 0x3F), band(rshift(c, 6), 0x3F), band(c, 0x3F)

		writeu8(output, outPos,     readu8(lookupValueToCharacter, v1))
		writeu8(output, outPos + 1, readu8(lookupValueToCharacter, v2))
		writeu8(output, outPos + 2, readu8(lookupValueToCharacter, v3))
		writeu8(output, outPos + 3, readu8(lookupValueToCharacter, v4))
	end

	return output
end

local function decode(input: buffer): buffer
	local inputLength = buflen(input)
	if inputLength == 0 then
		return buffer.create(0)
	end

	local inputChunks = math.ceil(inputLength / 4)
	local inputPadding = 0
	if readu8(input, inputLength - 1) == padding then inputPadding += 1 end
	if readu8(input, inputLength - 2) == padding then inputPadding += 1 end

	local outputLength = inputChunks * 3 - inputPadding
	local output = buffer.create(outputLength)

	for chunkIndex = 1, inputChunks - 1 do
		local inPos, outPos = (chunkIndex - 1) * 4, (chunkIndex - 1) * 3
		local v1 = readu8(lookupCharacterToValue, readu8(input, inPos))
		local v2 = readu8(lookupCharacterToValue, readu8(input, inPos + 1))
		local v3 = readu8(lookupCharacterToValue, readu8(input, inPos + 2))
		local v4 = readu8(lookupCharacterToValue, readu8(input, inPos + 3))

		local chunk = bor(lshift(v1, 18), lshift(v2, 12), lshift(v3, 6), v4)

		writeu8(output, outPos,     rshift(chunk, 16))
		writeu8(output, outPos + 1, band(rshift(chunk, 8), 0xFF))
		writeu8(output, outPos + 2, band(chunk, 0xFF))
	end

	local inPos, outPos = (inputChunks - 1) * 4, (inputChunks - 1) * 3
	local v1 = readu8(lookupCharacterToValue, readu8(input, inPos))
	local v2 = readu8(lookupCharacterToValue, readu8(input, inPos + 1))
	local v3 = readu8(lookupCharacterToValue, readu8(input, inPos + 2))
	local v4 = readu8(lookupCharacterToValue, readu8(input, inPos + 3))

	local chunk = bor(lshift(v1, 18), lshift(v2, 12), lshift(v3, 6), v4)

	if inputPadding <= 2 then
		writeu8(output, outPos, rshift(chunk, 16))
		if inputPadding <= 1 then
			writeu8(output, outPos + 1, band(rshift(chunk, 8), 0xFF))
			if inputPadding == 0 then
				writeu8(output, outPos + 2, band(chunk, 0xFF))
			end
		end
	end

	return output
end

return {
	encode = encode,
	decode = decode,
}