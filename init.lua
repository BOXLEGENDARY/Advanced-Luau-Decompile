--!optimize 2
--!nolint UnknownGlobal

local ENABLED_REMARKS = {
	COLD_REMARK = false,
	INLINE_REMARK = false -- currently unused
}
local DECOMPILER_TIMEOUT = 2 -- seconds
local READER_FLOAT_PRECISION = 7 -- up to 99
local USE_TYPE_INFO = true -- allow adding types to function parameters (ex. p1: string, p2: number)
local LIST_USED_GLOBALS = true -- list all (non-Roblox!!) globals used in the script as a top comment
local DECODE_AS_BASE64 = false -- Decodes the bytecode as base64 if it's returned as such.
local USE_IN_STUDIO = false -- Toggles Roblox Studio mode, which allows for this to be used in
local Debug = false -- true / show all debug loading in console | false / show some debug
local GitHubUrlShow = false -- work only u set Debug = true
-----------------------------------------------------------------
-- new funtion
-- rewrite to support exploits
-- better support for Roblox Studio
-- Base64 decoding supprot
-- nice to meet you this is a frist time and last time to update Good Luck  
-- special thanks w.a.e and break-core
-- fact: i only upgraded [ Implementations luau reader ] and other i use from break-core
-------------------------------------------------------------------

-- For studio, put your bytecode here.
local input = ``

local LoadFromUrl

LoadFromUrl = function(moduleName)
    local BASE_USER = "BOXLEGENDARY"
    local BASE_BRANCH = "main"
    local BASE_URL = "https://raw.githubusercontent.com/%s/LuauDecompile/%s/%s.lua"

    local function log(level, message, ...)
        local fullMessage = select("#", ...) > 0 and message:format(...) or message

        if not Debug then
            if level ~= "ERROR" and level ~= "FATAL" and level ~= "SUCCESS" then
                return
            end
        end

        if level == "FATAL" then
            error(fullMessage, 2)
        elseif level == "ERROR" or level == "WARN" or level == "INFO" or level == "SUCCESS" then
            warn(fullMessage)
        else
            print(fullMessage)
        end
    end

    local debugID = tostring(math.random(0, 999999))
    log("INFO", "----- LoadFromUrl started (debugID: LD-%s) -----", debugID)

    if type(moduleName) ~= "string" then
        log("FATAL", "Invalid moduleName type. Expected string but got %s", type(moduleName))
    elseif #moduleName == 0 then
        log("FATAL", "Module name is an empty string")
    else
        log("INFO", "Module name validated: %s", moduleName)
    end

    local formattedUrl = string.format(BASE_URL, BASE_USER, BASE_BRANCH, moduleName)

    if GitHubUrlShow then
        log("INFO", "Prepared GitHub URL for fetch: %s", formattedUrl)
    end

    local httpSuccess, response = pcall(function()
        log("INFO", "Attempting HttpGet from URL...")
        local result = game:HttpGet(formattedUrl, true)
        log("INFO", "HttpGet succeeded, received %d bytes", #result)
        return result
    end)

    if not httpSuccess then
        log("FATAL", "HttpGet failed for module '%s'. Reason: %s", moduleName, tostring(response))
    end

    if type(response) ~= "string" then
        log("FATAL", "HttpGet response type invalid. Expected string but got %s", type(response))
    elseif #response == 0 then
        log("FATAL", "HttpGet response empty for module '%s'", moduleName)
    else
        log("INFO", "Response content valid, length: %d bytes", #response)
    end

    log("INFO", "Compiling fetched code for module '%s'", moduleName)
    local compileSuccess, compiledOrError = pcall(loadstring, response)
    if not compileSuccess then
        log("FATAL", "Compilation failed for module '%s'. Error: %s", moduleName, tostring(compiledOrError))
    end

    local compiledType = type(compiledOrError)
    log("INFO", "loadstring returned type: %s", compiledType)

    if compiledType ~= "function" then
        log("FATAL", "Invalid module return type. Expected function but got %s", compiledType)
    end

    log("INFO", "Calling compiled function for module '%s'", moduleName)
    local execSuccess, funcResult = pcall(compiledOrError)
    if not execSuccess then
        log("FATAL", "Runtime error inside module '%s' function: %s", moduleName, tostring(funcResult))
    end
    log("SUCCESS", "Module '%s' executed and returned successfully", moduleName)
    return funcResult
end
local Implementations = LoadFromUrl("Implementations")
local Reader = LoadFromUrl("Reader")
local Strings = LoadFromUrl("Strings")
local Luau = LoadFromUrl("Luau")
local Base64 = LoadFromUrl("Base64")

local function LoadFlag(name)
	local success, result = pcall(function()
		return game:GetFastFlag(name)
	end)

	if success then
		return result
	end

	return true -- assume the test ended and it was successful
end
local LuauCompileUserdataInfo = LoadFlag("LuauCompileUserdataInfo")

local LuauOpCode = Luau.OpCode
local LuauBytecodeTag = Luau.BytecodeTag
local LuauBytecodeType = Luau.BytecodeType
local LuauCaptureType = Luau.CaptureType
local LuauBuiltinFunction = Luau.BuiltinFunction
local LuauProtoFlag = Luau.ProtoFlag

local toBoolean = Implementations.toBoolean
local toEscapedString = Implementations.toEscapedString
local formatIndexString = Implementations.formatIndexString
local padLeft = Implementations.padLeft
local padRight = Implementations.padRight
local isGlobal = Implementations.isGlobal

Reader:Set(READER_FLOAT_PRECISION)

local function Decompile(bytecode)
	local bytecodeVersion, typeEncodingVersion

	local reader = Reader.new(bytecode)

	-- step 1: collect information from the bytecode
	local function disassemble()
		if bytecodeVersion >= 4 then
			-- type encoding did not exist before this version
			typeEncodingVersion = reader:nextByte()
		end

		local stringTable = {}
		local function readStringTable()
			local amountOfStrings = reader:nextVarInt() -- or, well, stringTable size.
			for i = 1, amountOfStrings do
				stringTable[i] = reader:nextString()
			end
		end

		local userdataTypes = {}
		local function readUserdataTypes()
			if LuauCompileUserdataInfo then
				while true do
					local index = reader:nextByte()
					if index == 0 then
						-- zero marks the end of type mapping
						break
					end

					local nameRef = reader:nextVarInt()
					userdataTypes[index] = nameRef
				end
			end
		end

		local protoTable = {}
		local function readProtoTable()
			local amountOfProtos = reader:nextVarInt() -- or protoTable size
			for i = 1, amountOfProtos do
				local protoId = i - 1 -- account for main proto

				local proto = {
					id = protoId,

					instructions = {},
					constants = {},
					captures = {}, -- upvalue references
					innerProtos = {},

					instructionLineInfo = {}
				}
				protoTable[protoId] = proto

				-- read header
				proto.maxStackSize = reader:nextByte()
				proto.numParams = reader:nextByte()
				proto.numUpvalues = reader:nextByte()
				proto.isVarArg = toBoolean(reader:nextByte())

				-- read flags and typeInfo if bytecode version includes that information
				if bytecodeVersion >= 4 then
					proto.flags = reader:nextByte()

					-- collect type info
					local resultTypedParams = {}
					local resultTypedUpvalues = {}
					local resultTypedLocals = {}

					-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/BytecodeBuilder.cpp#L752
					local allTypeInfoSize = reader:nextVarInt()

					local hasTypeInfo = allTypeInfoSize > 0 -- we don't have any type info if the size is zero.
					proto.hasTypeInfo = hasTypeInfo

					if hasTypeInfo then
						local totalTypedParams = allTypeInfoSize
						local totalTypedUpvalues = 0
						local totalTypedLocals = 0

						if typeEncodingVersion > 1 then
							-- much more info is encoded in next versions
							totalTypedParams = reader:nextVarInt()
							totalTypedUpvalues = reader:nextVarInt()
							totalTypedLocals = reader:nextVarInt()
						end

						local function readTypedParams()
							local typedParams = resultTypedParams
							if totalTypedParams > 0 then
								typedParams = reader:nextBytes(totalTypedParams) -- array of uint8
								-- first value is always "function"
								-- we don't care about that.
								table.remove(typedParams, 1)
								-- second value is the amount of typed params
								table.remove(typedParams, 1)
							end
							return typedParams
						end
						local function readTypedUpvalues()
							local typedUpvalues = resultTypedUpvalues
							if totalTypedUpvalues > 0 then
								for i = 1, totalTypedUpvalues do
									local upvalueType = reader:nextByte()

									-- info on the upvalue at index `i`
									local info = {
										type = upvalueType
									}
									typedUpvalues[i] = info
								end
							end
							return typedUpvalues
						end
						local function readTypedLocals()
							local typedLocals = resultTypedLocals
							if totalTypedLocals > 0 then
								for i = 1, totalTypedLocals do
									local localType = reader:nextByte()
									-- Register is locals' place in the stack
									local localRegister = reader:nextByte() -- accounts for function params!
									-- PC - Program Counter
									local localStartPC = reader:nextVarInt() + 1
									-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/BytecodeBuilder.cpp#L749
									-- if you want to know why we get endPC like that
									local localEndPC = reader:nextVarInt() + localStartPC - 1

									-- info on the local at index `i`
									local info = {
										type = localType,
										register = localRegister,
										startPC = localStartPC,
										--endPC = localEndPC -- unused in the disassembler
									}
									typedLocals[i] = info
								end
							end
							return typedLocals
						end

						resultTypedParams = readTypedParams()
						resultTypedUpvalues = readTypedUpvalues()
						resultTypedLocals = readTypedLocals()
					end

					proto.typedParams = resultTypedParams
					proto.typedUpvalues = resultTypedUpvalues
					proto.typedLocals = resultTypedLocals
				end

				-- total number of instructions
				proto.sizeInstructions = reader:nextVarInt()
				for i = 1, proto.sizeInstructions do
					local encodedInstruction = reader:nextUInt32()
					proto.instructions[i] = encodedInstruction
				end

				-- total number of constants
				proto.sizeConstants = reader:nextVarInt()
				for i = 1, proto.sizeConstants do
					local constValue

					local constType = reader:nextByte()
					if constType == LuauBytecodeTag.LBC_CONSTANT_BOOLEAN then
						-- 1 = true, 0 = false
						constValue = toBoolean(reader:nextByte())
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_NUMBER then
						constValue = reader:nextDouble()
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_STRING then
						local stringId = reader:nextVarInt()
						constValue = stringTable[stringId]
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_IMPORT then
						-- imports are globals from the environment
						-- examples: math.random, print, coroutine.wrap

						local id = reader:nextUInt32()

						local indexCount = bit32.rshift(id, 30)

						local cacheIndex1 = bit32.band(bit32.rshift(id, 20), 0x3FF)
						local cacheIndex2 = bit32.band(bit32.rshift(id, 10), 0x3FF)
						local cacheIndex3 = bit32.band(bit32.rshift(id, 0), 0x3FF)

						local importTag = ""

						if indexCount == 1 then
							local k1 = proto.constants[cacheIndex1 + 1]
							importTag ..= tostring(k1.value)
						elseif indexCount == 2 then
							local k1 = proto.constants[cacheIndex1 + 1]
							local k2 = proto.constants[cacheIndex2 + 1]
							importTag ..= tostring(k1.value) .. "."
							importTag ..= tostring(k2.value)
						elseif indexCount == 3 then
							local k1 = proto.constants[cacheIndex1 + 1]
							local k2 = proto.constants[cacheIndex2 + 1]
							local k3 = proto.constants[cacheIndex3 + 1]
							importTag ..= tostring(k1.value) .. "."
							importTag ..= tostring(k2.value) .. "."
							importTag ..= tostring(k3.value)
						end

						constValue = importTag
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_TABLE then
						local sizeTable = reader:nextVarInt()
						local tableKeys = {}

						for i = 1, sizeTable do
							local keyStringId = reader:nextVarInt() + 1
							table.insert(tableKeys, keyStringId)
						end

						constValue = {
							size = sizeTable,
							keys = tableKeys
						}
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_CLOSURE then
						local closureId = reader:nextVarInt() + 1
						constValue = closureId
					elseif constType == LuauBytecodeTag.LBC_CONSTANT_VECTOR then
						local x, y, z, w = reader:nextFloat(), reader:nextFloat(), reader:nextFloat(), reader:nextFloat()
						if w == 0 then
							constValue = "Vector3.new(".. x ..", ".. y ..", ".. z ..")"
						else
							constValue = "vector.create(".. x ..", ".. y ..", ".. z ..", ".. w ..")"
						end
					elseif constType ~= LuauBytecodeTag.LBC_CONSTANT_NIL then
						-- this is not supposed to happen. result is likely malformed
					end

					-- info on the constant at index `i`
					local info = {
						type = constType,
						value = constValue
					}
					proto.constants[i] = info
				end

				-- total number of protos inside this proto
				proto.sizeInnerProtos = reader:nextVarInt()
				for i = 1, proto.sizeInnerProtos do
					local protoId = reader:nextVarInt()
					proto.innerProtos[i] = protoTable[protoId]
				end

				-- lineDefined is the line function starts on
				proto.lineDefined = reader:nextVarInt()

				-- protoDebugNameId is the string id of the function's name if it is not unnamed
				local protoDebugNameId = reader:nextVarInt()
				proto.name = stringTable[protoDebugNameId]

				-- references:
				-- https://github.com/luau-lang/luau/blob/0.655/Compiler/src/BytecodeBuilder.cpp#L888
				-- https://github.com/uniquadev/LuauVM/blob/master/VM/luau/lobject.lua
				local hasLineInfo = toBoolean(reader:nextByte())
				proto.hasLineInfo = hasLineInfo

				if hasLineInfo then
					-- log2 of the line gap between instructions
					local lineGapLog2 = reader:nextByte()

					local baselineSize = bit32.rshift(proto.sizeInstructions - 1, lineGapLog2) + 1

					local lastOffset = 0
					local lastLine = 0

					-- line number as a delta from baseline for each instruction
					local smallLineInfo = {}
					-- one entry for each bit32.lshift(1, lineGapLog2) instructions
					local absLineInfo = {}
					-- ready to read line info
					local resultLineInfo = {}

					for i, instruction in proto.instructions do
						-- i don't understand how this works. we mostly need signed, but sometimes we need unsigned?
						-- help please. if you understand
						local byte = reader:nextSignedByte()

						-- line numbers unexpectedly dropped/increased by 255 (or 256?) because i set delta to just lastOffset + byte
						-- the solution: (lastOffset + byte) & 0xFF.
						-- shoutout to https://github.com/ActualMasterOogway/Iridium/ for finding this fix
						local delta = bit32.band(lastOffset + byte, 0xFF)
						smallLineInfo[i] = delta

						lastOffset = delta
					end

					for i = 1, baselineSize do
						-- if we read unsigned int32 here we're doomed!!!!!!!! for eternity!!!!!!!!!
						local largeLineChange = lastLine + reader:nextInt32()
						absLineInfo[i] = largeLineChange

						lastLine = largeLineChange
					end

					for i, line in smallLineInfo do
						local absIndex = bit32.rshift(i - 1, lineGapLog2) + 1

						local absLine = absLineInfo[absIndex]
						local resultLine = line + absLine

						resultLineInfo[i] = resultLine
					end

					proto.lineInfoSize = lineGapLog2
					proto.instructionLineInfo = resultLineInfo
				end

				-- debug info is not present in Roblox and that's sad
				-- no variable names...
				local hasDebugInfo = toBoolean(reader:nextByte())
				proto.hasDebugInfo = hasDebugInfo

				if hasDebugInfo then
					local totalDebugLocals = reader:nextVarInt()
					local function readDebugLocals()
						local debugLocals = {}

						for i = 1, totalDebugLocals do
							local localName = stringTable[reader:nextVarInt()]
							local localStartPC = reader:nextVarInt()
							local localEndPC = reader:nextVarInt()
							local localRegister = reader:nextByte()

							-- debug info on the local at index `i`
							local info = {
								name = localName,
								startPC = localStartPC,
								endPC = localEndPC,
								register = localRegister
							}
							debugLocals[i] = info
						end

						return debugLocals
					end
					proto.debugLocals = readDebugLocals()

					local totalDebugUpvalues = reader:nextVarInt()
					local function readDebugUpvalues()
						local debugUpvalues = {}

						for i = 1, totalDebugUpvalues do
							local upvalueName = stringTable[reader:nextVarInt()]

							-- debug info on the upvalue at index `i`
							local info = {
								name = upvalueName
							}
							debugUpvalues[i] = info
						end

						return debugUpvalues
					end
					proto.debugUpvalues = readDebugUpvalues()
				end
			end
		end

		-- read needs to be done in proper order
		readStringTable()
		if bytecodeVersion > 5 then
			readUserdataTypes()
		end
		readProtoTable()

		if #userdataTypes > 0 then
			warn("please send the bytecode to me so i can add support for userdata types. thanks!")
		end

		local mainProtoId = reader:nextVarInt()
		return mainProtoId, protoTable
	end
	-- step 2: organize information for decompilation
	local function organize()
		-- provides proto name and line along with the issue in a warning message
		local function reportProtoIssue(proto, issue)
			local protoIdentifier = `[{proto.name or "unnamed"}:{proto.lineDefined or -1}]`
			warn(protoIdentifier .. ": " .. issue)
		end

		local mainProtoId, protoTable = disassemble()

		local mainProto = protoTable[mainProtoId]
		mainProto.main = true

		-- collected operation data
		local registerActions = {}

		local function baseProto(proto)
			local protoRegisterActions = {}

			-- this needs to be done here.
			local protoActionData = {
				proto = proto,
				actions = protoRegisterActions
			}
			registerActions[proto.id] = protoActionData

			local instructions = proto.instructions
			local innerProtos = proto.innerProtos
			local constants = proto.constants
			local captures = proto.captures
			local flags = proto.flags

			-- collect all captures past the base instruction index
			local function collectCaptures(baseIndex, proto)
				local numUpvalues = proto.numUpvalues
				if numUpvalues > 0 then
					local _captures = proto.captures

					for i = 1, numUpvalues do
						local capture = instructions[baseIndex + i]

						local captureType = Luau:INSN_A(capture)
						local sourceRegister = Luau:INSN_B(capture)

						if captureType == LuauCaptureType.LCT_VAL or captureType == LuauCaptureType.LCT_REF then
							_captures[i - 1] = sourceRegister
						elseif captureType == LuauCaptureType.LCT_UPVAL then
							-- capture of a capture. haha..
							_captures[i - 1] = captures[sourceRegister]
						end
					end
				end
			end

			local function writeFlags()
				local decodedFlags = {}

				if proto.main then
					-- what we are dealing with here is mainFlags
					-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/Compiler.cpp#L4188

					--decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_MODULE))
				else
					-- normal protoFlags
					-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/Compiler.cpp#L287

					--decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_FUNCTION))
					--decodedFlags.cold = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_COLD))
				end

				-- update flags entry
				flags = decodedFlags
				proto.flags = decodedFlags
			end
			local function writeInstructions()
				local auxSkip = false

				local opCodeHandlers = {
					-- Empty actions for these opcodes
					["NOP"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction(nil, nil) end,
					["BREAK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction(nil, nil) end,
					["NATIVECALL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction(nil, nil) end,
					["LOADNIL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}) end,
					["LOADB"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B, C}) end,
					["LOADN"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD}) end,
					["LOADK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {D}) end,
					["MOVE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}) end,
					["GETGLOBAL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {aux}) end,
					["SETGLOBAL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {aux}) end,
					["GETUPVAL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B}) end,
					["SETUPVAL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B}) end,
					["CLOSEUPVALS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, nil) end,
					["GETIMPORT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {D, aux}) end,
					["GETTABLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["SETTABLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["GETTABLEKS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C, aux}) end,
					["SETTABLEKS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C, aux}) end,
					["GETTABLEN"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["SETTABLEN"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["NEWCLOSURE"] = function(A, B, C, sD, D, E, aux, registerAction)
						registerAction({A}, {D})
						local proto = innerProtos[D + 1]
						collectCaptures(index, proto)
						baseProto(proto)
					end,
					["DUPCLOSURE"] = function(A, B, C, sD, D, E, aux, registerAction)
						registerAction({A}, {D})
						local proto = protoTable[constants[D + 1].value - 1]
						collectCaptures(index, proto)
						baseProto(proto)
					end,
					["NAMECALL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C, aux}) end,
					["CALL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B, C}) end,
					["RETURN"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B}) end,
					["JUMP"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {sD}) end,
					["JUMPBACK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {sD}) end,
					["JUMPIF"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD}) end,
					["JUMPIFNOT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD}) end,
					["JUMPIFEQ"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["JUMPIFLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["JUMPIFLT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["JUMPIFNOTEQ"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["JUMPIFNOTLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["JUMPIFNOTLT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, aux}, {sD}) end,
					["ADD"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["SUB"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["MUL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["DIV"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["MOD"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["POW"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["ADDK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["SUBK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["MULK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["DIVK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["MODK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["POWK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["AND"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["OR"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["ANDK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["ORK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["CONCAT"] = function(A, B, C, sD, D, E, aux, registerAction)
						local registers = {A}
						for reg = B, C do
							table.insert(registers, reg)
						end
						registerAction(registers)
					end,
					["NOT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}) end,
					["MINUS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}) end,
					["LENGTH"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}) end,
					["NEWTABLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {B, aux}) end,
					["DUPTABLE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {D}) end,
					["SETLIST"] = function(A, B, C, sD, D, E, aux, registerAction)
						if C ~= 0 then
							local registers = {A, B}
							for i = 1, C - 2 do -- account for target and source registers
								table.insert(registers, A + i)
							end
							registerAction(registers, {aux, C})
						else
							registerAction({A, B}, {aux, C})
						end
					end,
					["FORNPREP"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, A+1, A+2}, {sD}) end,
					["FORNLOOP"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD}) end,
					["FORGLOOP"] = function(A, B, C, sD, D, E, aux, registerAction)
						local numVariableRegisters = bit32.band(aux, 0xFF)
						local registers = {}
						for regIndex = 1, numVariableRegisters do
							table.insert(registers, A + regIndex)
						end
						registerAction(registers, {sD, aux})
					end,
					["FORGPREP_INEXT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, A+1}) end,
					["FORGPREP_NEXT"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, A+1}) end,
					["FORGPREP"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD}) end,
					["GETVARARGS"] = function(A, B, C, sD, D, E, aux, registerAction)
						if B ~= 0 then
							local registers = {A}
							-- i hope this works and it is not reg = 1
							for reg = 0, B - 1 do
								table.insert(registers, A + reg)
							end
							registerAction(registers, {B})
						else
							registerAction({A}, {B})
						end
					end,
					["PREPVARARGS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {A}) end,
					["LOADKX"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {aux}) end,
					["JUMPX"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {E}) end,
					["COVERAGE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {E}) end,
					["JUMPXEQKNIL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD, aux}) end,
					["JUMPXEQKB"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD, aux}) end,
					["JUMPXEQKN"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD, aux}) end,
					["JUMPXEQKS"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A}, {sD, aux}) end,
					["CAPTURE"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction(nil, nil) end,
					["SUBRK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, C}, {B}) end,
					["DIVRK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, C}, {B}) end,
					["IDIV"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B, C}) end,
					["IDIVK"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({A, B}, {C}) end,
					["FASTCALL"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({}, {A, C}) end,
					["FASTCALL1"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({B}, {A, C}) end,
					["FASTCALL2"] = function(A, B, C, sD, D, E, aux, registerAction)
						local sourceArgumentRegister2 = bit32.band(aux, 0xFF)
						registerAction({B, sourceArgumentRegister2}, {A, C})
					end,
					["FASTCALL2K"] = function(A, B, C, sD, D, E, aux, registerAction) registerAction({B}, {A, C, aux}) end,
					["FASTCALL3"] = function(A, B, C, sD, D, E, aux, registerAction)
						local sourceArgumentRegister2 = bit32.band(aux, 0xFF)
						local sourceArgumentRegister3 = bit32.rshift(sourceArgumentRegister2, 8)
						registerAction({B, sourceArgumentRegister2, sourceArgumentRegister3}, {A, C})
					end,
				}

				for index, instruction in instructions do
					if auxSkip then
						-- we are currently on an aux of a previous instruction
						-- there is no need to do any work here.
						auxSkip = false
						continue
					end

					local opCodeInfo = LuauOpCode[Luau:INSN_OP(instruction)]
					if not opCodeInfo then
						-- this is serious! reportProtoIssue(proto, `invalid instruction at index "{index}"!`)
						continue
					end

					local opCodeName = opCodeInfo.name
					local opCodeType = opCodeInfo.type
					local opCodeIsAux = opCodeInfo.aux == true

					-- information in the instruction that we will use
					local A, B, C
					local sD, D, E
					local aux

					-- creates an action from provided data and registers it.
					local function registerAction(usedRegisters, extraData, hide)
						local data = {
							usedRegisters = usedRegisters or {},
							extraData = extraData,
							opCode = opCodeInfo,
							hide = hide
						}
						table.insert(protoRegisterActions, data)
					end

					-- handle reading information based on the op code type
					if opCodeType == "A" then
						A = Luau:INSN_A(instruction)
					elseif opCodeType == "E" then
						E = Luau:INSN_E(instruction)
					elseif opCodeType == "AB" then
						A = Luau:INSN_A(instruction)
						B = Luau:INSN_B(instruction)
					elseif opCodeType == "AC" then
						A = Luau:INSN_A(instruction)
						C = Luau:INSN_C(instruction)
					elseif opCodeType == "ABC" then
						A = Luau:INSN_A(instruction)
						B = Luau:INSN_B(instruction)
						C = Luau:INSN_C(instruction)
					elseif opCodeType == "AD" then
						A = Luau:INSN_A(instruction)
						D = Luau:INSN_D(instruction)
					elseif opCodeType == "AsD" then
						A = Luau:INSN_A(instruction)
						sD = Luau:INSN_sD(instruction)
					elseif opCodeType == "sD" then
						sD = Luau:INSN_sD(instruction)
					end

					-- handle aux
					if opCodeIsAux then
						auxSkip = true

						-- empty action for aux
						registerAction(nil, nil, true)

						-- aux is the next instruction
						aux = instructions[index + 1]
					end

					-- Use the table mapping instead of the long elseif chain
					local handler = opCodeHandlers[opCodeName]
					if handler then
						handler(A, B, C, sD, D, E, aux, registerAction)
					end
				end
			end

			writeFlags()
			writeInstructions()
		end
		baseProto(mainProto)

		return mainProtoId, registerActions, protoTable
	end
	-- step 3: turn the result into a string
	local function finalize(mainProtoId, registerActions, protoTable)
		local finalResult = ""

		local totalParameters = 0
		-- array of used globals for further output
		local usedGlobals = {}

		-- should `key` be logged in usedGlobals?
		local function isValidGlobal(key)
			return not table.find(usedGlobals, key) and not isGlobal(key)
		end

		-- received result. embed final things here.
		local function processResult(result)
			local embed = ""

			if LIST_USED_GLOBALS and #usedGlobals > 0 then
				embed ..= string.format(Strings.USED_GLOBALS, table.concat(usedGlobals, ", "))
			end

			return embed .. result
		end

	if DECOMPILER_MODE == "disasm" then -- disassembler
		local result = ""

		local function writeActions(protoActions)
			local actions = protoActions.actions
			local proto = protoActions.proto

			local instructionLineInfo = proto.instructionLineInfo
			local innerProtos = proto.innerProtos
			local constants = proto.constants
			local captures = proto.captures
			local flags = proto.flags

			local numParams = proto.numParams

			SHOW_INSTRUCTION_LINES = SHOW_INSTRUCTION_LINES and #instructionLineInfo > 0

			-- for proper `goto` handling
			local jumpMarkers = {}
			local function makeJumpMarker(index)
				index -= 1

				local numMarkers = jumpMarkers[index] or 0
				jumpMarkers[index] = numMarkers + 1
			end

			-- for easier parameter differentiation
			totalParameters += numParams

			-- support for mainFlags
			if proto.main then
				-- if there is a possible way to check for --!optimize please let me know
				if flags.native then
					result ..= "--!native" .. "\n"
				end
			end

			for i, action in actions do
				if action.hide then
					-- skip this action. either hidden or just aux that is needed for proper line info
					continue
				end

				local usedRegisters = action.usedRegisters
				local extraData = action.extraData
				local opCodeInfo = action.opCode

				local opCodeName = opCodeInfo.name

				local function handleJumpMarkers()
					local numJumpMarkers = jumpMarkers[i]
					if numJumpMarkers then
						jumpMarkers[i] = nil

						--if string.find(opCodeName, "JUMP") then
						-- it's much more complicated
						--	result ..= "else\n"

						--	local newJumpOffset = i + extraData[1] + 1
						--	makeJumpMarker(newJumpOffset)
						--else
						-- it's just a one way condition
						for i = 1, numJumpMarkers do
							result ..= "end\n"
						end
						--end
					end
				end

				local function writeHeader()
					local index
						index = ""
					end
					local name
						name = ""
					end
					local line
						line = ""
					end
					result ..= index .." ".. line .. name
				end

				local function writeOperationBody()
					local function formatRegister(register)
						local parameterRegister = register + 1 -- parameter registers start from 0
						if parameterRegister < numParams + 1 then
							-- this means we are using preserved parameter register
							return "p".. ((totalParameters - numParams) + parameterRegister)
						end
						return "v".. (register - numParams)
					end
					local function formatUpvalue(register)
						return "u_v".. register
					end
					local function formatProto(proto)
						local name = proto.name
						local numParams = proto.numParams
						local isVarArg = proto.isVarArg
						local isTyped = proto.hasTypeInfo and USE_TYPE_INFO
						local flags = proto.flags
						local typedParams = proto.typedParams
						local protoBody = ""

						-- attribute support
						if flags.native then
							if flags.cold and ENABLED_REMARKS.COLD_REMARK then
								-- function is marked cold and is deemed not profitable to compile natively
								-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/Compiler.cpp#L285
								protoBody ..= string.format(Strings.DECOMPILER_REMARK, "This function is marked cold and is not compiled natively")
							end
							protoBody ..= "@native "
						end

						-- if function has a name, add it
						if name then
							protoBody = "local function ".. name
						else
							protoBody = "function"
						end

						-- now build parameters
						protoBody ..= "("
						for index = 1, numParams do
							local parameterBody = "p".. (totalParameters + index)
							-- if has type info, apply it
							if isTyped then
								local parameterType = typedParams[index]
								-- not sure if parameterType always exists
								if parameterType then
									parameterBody ..= ": ".. Luau:GetBaseTypeString(parameterType, true)
								end
							end
							-- if not last parameter
							if index ~= numParams then
								parameterBody ..= ", "
							end
							protoBody ..= parameterBody
						end
						if isVarArg then
							if numParams > 0 then
								-- top it off with ...
								protoBody ..= ", ..."
							else
								protoBody ..= "..."
							end
						end
						protoBody ..= ")\n"

						return protoBody
					end
					local function formatConstantValue(k)
						if k.type == LuauBytecodeTag.LBC_CONSTANT_VECTOR then
							return k.value
						else
							if type(tonumber(k.value)) == "number" then
								return tonumber(string.format(`%0.{READER_FLOAT_PRECISION}f`, k.value))
							else
								return toEscapedString(k.value)
							end
						end
					end
					local function writeProto(register, proto)
						local protoBody = formatProto(proto)
						local name = proto.name
						if name then
							result ..= "\n".. protoBody
							writeActions(registerActions[proto.id])
							result ..= "end\n".. formatRegister(register) .." = ".. name
						else
							result ..= formatRegister(register) .." = ".. protoBody
							writeActions(registerActions[proto.id])
							result ..= "end"
						end
					end

					-- Handler for specific opCodeName actions
					local opCodeBodyHandlers = {
						["LOADNIL"] = function()
							local targetRegister = usedRegisters[1]
							result ..= formatRegister(targetRegister) .." = nil"
						end,
						["LOADB"] = function() -- load boolean
							local targetRegister = usedRegisters[1]
							local value = toBoolean(extraData[1])
							local jumpOffset = extraData[2]
							result ..= formatRegister(targetRegister) .." = ".. toEscapedString(value)
							if jumpOffset ~= 0 then
								-- skip over next LOADB?
								result ..= string.format(" +%i", jumpOffset)
							end
						end,
						["LOADN"] = function() -- load number literal
							local targetRegister = usedRegisters[1]
							local value = extraData[1]
							result ..= formatRegister(targetRegister) .." = ".. value
						end,
						["LOADK"] = function() -- load constant
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. value
						end,
						["MOVE"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister)
						end,
						["GETGLOBAL"] = function()
							local targetRegister = usedRegisters[1]
							-- formatConstantValue uses toEscapedString which we don't want here
							local globalKey = tostring(constants[extraData[1] + 1].value)
							if LIST_USED_GLOBALS and isValidGlobal(globalKey) then
								table.insert(usedGlobals, globalKey)
							end
							result ..= formatRegister(targetRegister) .." = ".. globalKey
						end,
						["SETGLOBAL"] = function()
							local sourceRegister = usedRegisters[1]
							local globalKey = tostring(constants[extraData[1] + 1].value)
							if LIST_USED_GLOBALS and isValidGlobal(globalKey) then
								table.insert(usedGlobals, globalKey)
							end
							result ..= globalKey .." = ".. formatRegister(sourceRegister)
						end,
						["GETUPVAL"] = function()
							local targetRegister = usedRegisters[1]
							local upvalueIndex = extraData[1]
							result ..= formatRegister(targetRegister) .." = ".. formatUpvalue(captures[upvalueIndex])
						end,
						["SETUPVAL"] = function()
							local sourceRegister = usedRegisters[1]
							local upvalueIndex = extraData[1]
							result ..= formatUpvalue(captures[upvalueIndex]) .." = ".. formatRegister(sourceRegister)
						end,
						["CLOSEUPVALS"] = function()
							local targetRegister = usedRegisters[1]
							result ..= "-- clear captures from back until: ".. targetRegister
						end,
						["GETIMPORT"] = function()
							local targetRegister = usedRegisters[1]
							local importIndex = extraData[1]
							local importIndices = extraData[2]
							-- we load imports into constants
							local import = tostring(constants[importIndex + 1].value)
							local totalIndices = bit32.rshift(importIndices, 30)
							if totalIndices == 1 then
								if LIST_USED_GLOBALS and isValidGlobal(import) then
									-- it is a non-Roblox global that we need to log
									table.insert(usedGlobals, import)
								end
							end
							result ..= formatRegister(targetRegister) .." = ".. import
						end,
						["GETTABLE"] = function()
							local targetRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							local indexRegister = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(tableRegister) .."[".. formatRegister(indexRegister) .."]"
						end,
						["SETTABLE"] = function()
							local sourceRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							local indexRegister = usedRegisters[3]
							result ..= formatRegister(tableRegister) .."[".. formatRegister(indexRegister) .."]" .." = ".. formatRegister(sourceRegister)
						end,
						["GETTABLEKS"] = function()
							local targetRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							--local slotIndex = extraData[1]
							local key = constants[extraData[2] + 1].value
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(tableRegister) .. formatIndexString(key)
						end,
						["SETTABLEKS"] = function()
							local sourceRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							--local slotIndex = extraData[1]
							local key = constants[extraData[2] + 1].value
							result ..= formatRegister(tableRegister) .. formatIndexString(key) .." = ".. formatRegister(sourceRegister)
						end,
						["GETTABLEN"] = function()
							local targetRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							local index = extraData[1] + 1
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(tableRegister) .."[".. index .."]"
						end,
						["SETTABLEN"] = function()
							local sourceRegister = usedRegisters[1]
							local tableRegister = usedRegisters[2]
							local index = extraData[1] + 1
							result ..= formatRegister(tableRegister) .."[".. index .."] = ".. formatRegister(sourceRegister)
						end,
						["NEWCLOSURE"] = function()
							local targetRegister = usedRegisters[1]
							local protoIndex = extraData[1] + 1
							local nextProto = innerProtos[protoIndex]
							writeProto(targetRegister, nextProto)
						end,
						["DUPCLOSURE"] = function()
							local targetRegister = usedRegisters[1]
							local protoIndex = extraData[1] + 1
							local nextProto = protoTable[constants[protoIndex].value - 1]
							writeProto(targetRegister, nextProto)
						end,
						["NAMECALL"] = function() -- must be followed by CALL
							--local targetRegister = usedRegisters[1]
							--local sourceRegister = usedRegisters[2]
							--local slotIndex = extraData[1]
							local method = tostring(constants[extraData[2] + 1].value)
							result ..= "-- :".. method
						end,
						["CALL"] = function()
							local baseRegister = usedRegisters[1]
							local numArguments = extraData[1] - 1
							local numResults = extraData[2] - 1
							-- NAMECALL instruction might provide us a method
							local namecallMethod = ""
							local argumentOffset = 0
							-- try searching for the NAMECALL instruction
							local precedingAction = actions[i - 1]
							if precedingAction then
								local precedingOpCode = precedingAction.opCode
								if precedingOpCode.name == "NAMECALL" then
									local precedingExtraData = precedingAction.extraData
									namecallMethod = ":".. tostring(constants[precedingExtraData[2] + 1].value)
									-- exclude self due to syntactic sugar
									numArguments -= 1
									argumentOffset += 1
									-- but self still needs to be counted...
								end
							end

							local arguments = {}
							for regIndex = 0, numArguments do
								table.insert(arguments, formatRegister(baseRegister + regIndex))
							end

							local returnRegisters = {}
							local function formatReturnRegisters()
								if numResults == 0 then
									return ""
								elseif numResults == 1 then
									return formatRegister(baseRegister) .." = "
								else
									for regIndex = 0, numResults - 1 do
										table.insert(returnRegisters, formatRegister(baseRegister + regIndex))
									end
									return table.concat(returnRegisters, ", ") .." = "
								end
							end

							result ..= formatReturnRegisters() .. formatRegister(baseRegister) .. namecallMethod .. "(" .. table.concat(arguments, ", ") .. ")"
						end,
						["RETURN"] = function()
							local baseRegister = usedRegisters[1]
							local numReturns = extraData[1] - 1

							local returns = {}
							for regIndex = 0, numReturns do
								table.insert(returns, formatRegister(baseRegister + regIndex))
							end

							if numReturns < 0 then
								result ..= "return"
							else
								result ..= "return ".. table.concat(returns, ", ")
							end
						end,
						["JUMP"] = function()
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "goto " .. targetIndex
							end
						end,
						["JUMPBACK"] = function()
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex >= 1 then
								makeJumpMarker(targetIndex)
								result ..= "goto " .. targetIndex
							end
						end,
						["JUMPIF"] = function()
							local targetRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFNOT"] = function()
							local targetRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if not ".. formatRegister(targetRegister) .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFEQ"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." == ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFLE"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." <= ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFLT"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." < ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFNOTEQ"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." ~= ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFNOTLE"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if not (".. formatRegister(targetRegister) .." <= ".. value ..") then goto ".. targetIndex .." end"
							end
						end,
						["JUMPIFNOTLT"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[1] + 1])
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if not (".. formatRegister(targetRegister) .." < ".. value ..") then goto ".. targetIndex .." end"
							end
						end,
						["ADD"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." + ".. formatRegister(sourceRegister2)
						end,
						["SUB"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." - ".. formatRegister(sourceRegister2)
						end,
						["MUL"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." * ".. formatRegister(sourceRegister2)
						end,
						["DIV"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." / ".. formatRegister(sourceRegister2)
						end,
						["MOD"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." % ".. formatRegister(sourceRegister2)
						end,
						["POW"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." ^ ".. formatRegister(sourceRegister2)
						end,
						["ADDK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." + ".. value
						end,
						["SUBK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." - ".. value
						end,
						["MULK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." * ".. value
						end,
						["DIVK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." / ".. value
						end,
						["MODK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." % ".. value
						end,
						["POWK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." ^ ".. value
						end,
						["AND"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." and ".. formatRegister(sourceRegister2)
						end,
						["OR"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister1) .." or ".. formatRegister(sourceRegister2)
						end,
						["ANDK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." and ".. value
						end,
						["ORK"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. formatRegister(sourceRegister) .." or ".. value
						end,
						["CONCAT"] = function()
							local targetRegister = usedRegisters[1]
							local sourceStartRegister = usedRegisters[2]
							local sourceEndRegister = usedRegisters[3]
							local concatRegisters = {}
							for regIndex = sourceStartRegister, sourceEndRegister do
								table.insert(concatRegisters, formatRegister(regIndex))
							end
							result ..= formatRegister(targetRegister) .." = ".. table.concat(concatRegisters, " .. ")
						end,
						["NOT"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							result ..= formatRegister(targetRegister) .." = not ".. formatRegister(sourceRegister)
						end,
						["MINUS"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							result ..= formatRegister(targetRegister) .." = -".. formatRegister(sourceRegister)
						end,
						["LENGTH"] = function()
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							result ..= formatRegister(targetRegister) .." = #".. formatRegister(sourceRegister)
						end,
						["NEWTABLE"] = function()
							local targetRegister = usedRegisters[1]
							local arraySize = extraData[1]
							local hashTableSize = extraData[2]
							result ..= formatRegister(targetRegister) .." = {} -- {array=".. arraySize ..", hash=".. hashTableSize .."}"
						end,
						["DUPTABLE"] = function()
							local targetRegister = usedRegisters[1]
							local tableTemplateIndex = extraData[1]
							result ..= formatRegister(targetRegister) .." = table.clone(".. formatConstantValue(constants[tableTemplateIndex + 1]) ..")"
						end,
						["SETLIST"] = function()
							local targetRegister = usedRegisters[1]
							local count = extraData[1]
							local base = extraData[2]
							local values = {}
							for regIndex = 0, count - 1 do
								table.insert(values, formatRegister(targetRegister + regIndex))
							end
							result ..= "table.insert(".. formatRegister(targetRegister) ..", {".. table.concat(values, ", ") .."})"
						end,
						["FORNPREP"] = function()
							local baseRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "for ".. formatRegister(baseRegister) ..", ".. formatRegister(baseRegister + 1) ..", ".. formatRegister(baseRegister + 2) .." do -- For Numeric Loop Prep (goto ".. targetIndex ..")"
							end
						end,
						["FORNLOOP"] = function()
							local baseRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(baseRegister + 1) ..">0 then ".. formatRegister(baseRegister) .." += ".. formatRegister(baseRegister + 2) .." else ".. formatRegister(baseRegister) .." -= ".. formatRegister(baseRegister + 2) .." end -- For Numeric Loop (goto ".. targetIndex ..")"
							end
						end,
						["FORGLOOP"] = function()
							local baseRegister = usedRegisters[1]
							local numVariables = extraData[1]
							local jumpOffset = extraData[2] + 1
							local targetIndex = i + jumpOffset
							local variables = {}
							for j = 0, numVariables - 1 do
								table.insert(variables, formatRegister(baseRegister + j))
							end
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "for ".. table.concat(variables, ", ") .." in ".. formatRegister(baseRegister) ..", ".. formatRegister(baseRegister + 1) .." do -- For Generic Loop (goto ".. targetIndex ..")"
							end
						end,
						["FORGPREP_INEXT"] = function()
							local baseRegister = usedRegisters[1]
							result ..= formatRegister(baseRegister) ..", ".. formatRegister(baseRegister + 1) .." = ipairs(".. formatRegister(baseRegister) ..") -- For Generic Loop Prep (ipairs)"
						end,
						["FORGPREP_NEXT"] = function()
							local baseRegister = usedRegisters[1]
							result ..= formatRegister(baseRegister) ..", ".. formatRegister(baseRegister + 1) .." = next(".. formatRegister(baseRegister) ..") -- For Generic Loop Prep (next)"
						end,
						["FORGPREP"] = function()
							local baseRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "do -- For Generic Loop Prep (goto ".. targetIndex ..")"
							end
						end,
						["GETVARARGS"] = function()
							local targetRegister = usedRegisters[1]
							local numReturns = extraData[1]
							local returns = {}
							for j = 0, numReturns - 1 do
								table.insert(returns, formatRegister(targetRegister + j))
							end
							result ..= table.concat(returns, ", ") .." = ..."
						end,
						["PREPVARARGS"] = function()
							local numFixedParams = extraData[1]
							result ..= "-- prepare varargs, ".. numFixedParams .." fixed parameters"
						end,
						["LOADKX"] = function()
							local targetRegister = usedRegisters[1]
							local constantIndex = extraData[1]
							local value = formatConstantValue(constants[constantIndex + 1])
							result ..= formatRegister(targetRegister) .." = ".. value
						end,
						["JUMPX"] = function()
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "goto ".. targetIndex
							end
						end,
						["COVERAGE"] = function()
							local blockId = extraData[1]
							result ..= "-- coverage block: ".. blockId
						end,
						["JUMPXEQKNIL"] = function()
							local targetRegister = usedRegisters[1]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." == nil then goto ".. targetIndex .." end"
							end
						end,
						["JUMPXEQKB"] = function()
							local targetRegister = usedRegisters[1]
							local value = toBoolean(extraData[2])
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." == ".. tostring(value) .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPXEQKN"] = function()
							local targetRegister = usedRegisters[1]
							local value = extraData[2]
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." == ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["JUMPXEQKS"] = function()
							local targetRegister = usedRegisters[1]
							local value = formatConstantValue(constants[extraData[2] + 1])
							local jumpOffset = extraData[1] + 1
							local targetIndex = i + jumpOffset
							if targetIndex <= #actions then
								makeJumpMarker(targetIndex)
								result ..= "if ".. formatRegister(targetRegister) .." == ".. value .." then goto ".. targetIndex .." end"
							end
						end,
						["CAPTURE"] = function()
							result ..= "-- capture instruction"
						end,
						["SUBRK"] = function() -- constant sub
							local targetRegister = usedRegisters[1]
							local constantRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. value .." - ".. formatRegister(constantRegister)
						end,
						["DIVRK"] = function() -- constant div
							local targetRegister = usedRegisters[1]
							local constantRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = ".. value .." / ".. formatRegister(constantRegister)
						end,
						["IDIV"] = function() -- floor division
							local targetRegister = usedRegisters[1]
							local sourceRegister1 = usedRegisters[2]
							local sourceRegister2 = usedRegisters[3]
							result ..= formatRegister(targetRegister) .." = math.floor(".. formatRegister(sourceRegister1) .." / ".. formatRegister(sourceRegister2) ..")"
						end,
						["IDIVK"] = function() -- floor division with 1 constant argument
							local targetRegister = usedRegisters[1]
							local sourceRegister = usedRegisters[2]
							local value = formatConstantValue(constants[extraData[1] + 1])
							result ..= formatRegister(targetRegister) .." = math.floor(".. formatRegister(sourceRegister) .." / ".. value ..")"
						end,
						["FASTCALL"] = function() -- reads info from the CALL instruction
							local functionId = LuauBuiltinFunction[extraData[1]]
							local numResults = extraData[2]
							result ..= "-- FASTCALL: ".. (functionId or "unknown") ..", Results: ".. numResults
						end,
						["FASTCALL1"] = function() -- 1 register argument
							local targetRegister = usedRegisters[1]
							local functionId = LuauBuiltinFunction[extraData[1]]
							local numResults = extraData[2]
							result ..= "-- FASTCALL1: ".. (functionId or "unknown") ..", Arg: ".. formatRegister(targetRegister) ..", Results: ".. numResults
						end,
						["FASTCALL2"] = function() -- 2 register arguments
							local targetRegister1 = usedRegisters[1]
							local targetRegister2 = usedRegisters[2]
							local functionId = LuauBuiltinFunction[extraData[1]]
							local numResults = extraData[2]
							result ..= "-- FASTCALL2: ".. (functionId or "unknown") ..", Arg1: ".. formatRegister(targetRegister1) ..", Arg2: ".. formatRegister(targetRegister2) ..", Results: ".. numResults
						end,
						["FASTCALL2K"] = function() -- 1 register argument and 1 constant argument
							local targetRegister = usedRegisters[1]
							local functionId = LuauBuiltinFunction[extraData[1]]
							local numResults = extraData[2]
							local constantValue = formatConstantValue(constants[extraData[3] + 1])
							result ..= "-- FASTCALL2K: ".. (functionId or "unknown") ..", Arg1: ".. formatRegister(targetRegister) ..", Arg2: ".. constantValue ..", Results: ".. numResults
						end,
						["FASTCALL3"] = function()
							local targetRegister1 = usedRegisters[1]
							local targetRegister2 = usedRegisters[2]
							local targetRegister3 = usedRegisters[3]
							local functionId = LuauBuiltinFunction[extraData[1]]
							local numResults = extraData[2]
							result ..= "-- FASTCALL3: ".. (functionId or "unknown") ..", Arg1: ".. formatRegister(targetRegister1) ..", Arg2: ".. formatRegister(targetRegister2) ..", Arg3: ".. formatRegister(targetRegister3) ..", Results: ".. numResults
						end,
					}

					local handler = opCodeBodyHandlers[opCodeName]
					if handler then
						handler()
					else
						-- Fallback for unhandled opcodes or complex ones not easily mapped
						result ..= "-- Unhandled opcode: " .. opCodeName
					end
				end

				writeHeader()
				writeOperationBody()
				handleJumpMarkers()
				result ..= "\n"
			end
		end

		writeActions(registerActions[mainProtoId])

		finalResult = processResult(result)
	end

	return finalResult
end

local success, result = pcall(function()
	local mainProtoId, registerActions, protoTable = organize()
	return finalize(mainProtoId, registerActions, protoTable)
end)

if not success then
	error(`Couldn't decompile bytecode: {tostring(result)}`, 2)
	return
end

local decomped

if DECODE_AS_BASE64 then
    local toDecode = buffer.fromstring(result)
    local decoded = Base64.decode(toDecode)
    decomped = Decompile(result)
else
    decomped = Decompile(result)
end
else
if DECODE_AS_BASE64 then
    local toDecode = buffer.fromstring(input)
    local decoded = Base64.decode(toDecode)
    local decomped = Decompile(buffer.tostring(decoded))
    warn("done decompiling:")
    game:GetService("ScriptEditorService"):UpdateSource(game.CoreGui.Decompiler.Init, decomped)
else
    local decomped, elapsedTime = Decompile(input)
    warn("done decompiling:")
    game:GetService("ScriptEditorService"):UpdateSource(game.CoreGui.Decompiler.Init, decomped)
end
end