--!optimize 2

local DEFAULT_OPTIONS = {
	EnabledRemarks = {
		ColdRemark = false,
		InlineRemark = true -- currently unused
	},
	DecompilerTimeout = 10, -- seconds
	DecompilerMode = "disasm", -- optdec/disasm
	ReaderFloatPrecision = 7, -- up to 99
	ShowDebugInformation = true, -- show trivial function and array allocation details
	ShowInstructionLines = true, -- show lines as they are in the source code
	ShowOperationIndex = true, -- show instruction index. used in jumps #n.
	ShowOperationNames = true,
	ShowTrivialOperations = false,
	UseTypeInfo = true, -- allow adding types to function parameters (ex. p1: string, p2: number)
	ListUsedGlobals = true, -- list all (non-Roblox!!) globals used in the script as a top comment
	ReturnElapsedTime = false -- return time it took to finish processing the bytecode
}

local function LoadFromUrl(x)
	local BASE_USER = "BOXLEGENDARY"
	local BASE_BRANCH = "main"
	local BASE_URL = "https://raw.githubusercontent.com/%s/ZDex/%s/%s.lua"

	local loadSuccess, loadResult = pcall(function()
		local formattedUrl = string.format(BASE_URL, BASE_USER, BASE_BRANCH, x)
		return game:HttpGet(formattedUrl, true)
	end)

	if not loadSuccess then
		warn(`({math.random()}) MОDULE FАILЕD ТO LOАD FRОM URL: {loadResult}.`)
		return
	end

	local success, result = pcall(loadstring, loadResult)
	if not success then
		warn(`({math.random()}) MОDULE FАILЕD ТO LOАDSТRING: {result}.`)
		return
	end

	if type(result) ~= "function" then
		warn(`MОDULE IS {tostring(result)} (function expected)`)
		return
	end

	return result()
end
local Implementations = LoadFromUrl("Implementations")
local Reader = LoadFromUrl("Reader")
local Strings = LoadFromUrl("Strings")
local Luau = LoadFromUrl("Luau")

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

local function Decompile(bytecode, options)
	local bytecodeVersion, typeEncodingVersion

	Reader:Set(options.ReaderFloatPrecision)

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

						local offsetChange = lastOffset + byte
						smallLineInfo[i] = offsetChange

						lastOffset = offsetChange
					end

					for i = 1, baselineSize do
						-- if we read unsigned int32 here we're doomed!!!!!! for eternity!!!!!!!!!
						local largeLineChange = lastLine + reader:nextInt32()
						absLineInfo[i - 1] = largeLineChange

						lastLine = largeLineChange
					end

					for i, line in smallLineInfo do
						local absIndex = bit32.rshift(i - 1, lineGapLog2)

						local absLine = absLineInfo[absIndex]
						local resultLine = line + absLine

						if lineGapLog2 <= 1 and (-line == absLine) then
							-- this just seems to happen
							resultLine += absLineInfo[absIndex + 1]
						end

						-- function inlining ruins everything
						if resultLine <= 0 then
							resultLine += 0x100
						end

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

					decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_MODULE))
				else
					-- normal protoFlags
					-- refer to: https://github.com/luau-lang/luau/blob/0.655/Compiler/src/Compiler.cpp#L287

					decodedFlags.native = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_FUNCTION))
					decodedFlags.cold = toBoolean(bit32.band(flags, LuauProtoFlag.LPF_NATIVE_COLD))
				end

				-- update flags entry
				flags = decodedFlags
				proto.flags = decodedFlags
			end
			local function writeInstructions()
				local auxSkip = false

				for index, instruction in instructions do
					if auxSkip then
						-- we are currently on an aux of a previous instruction
						-- there is no need to do any work here.
						auxSkip = false
						continue
					end

					local opCodeInfo = LuauOpCode[Luau:INSN_OP(instruction)]
					if not opCodeInfo then
						-- this is serious!
						reportProtoIssue(proto, `invalid instruction at index "{index}"!`)
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

					-- it would be faster if we did this comparing opCode index
					-- rather than name, but it would be suffering to code and read
					if opCodeName == "NOP" or opCodeName == "BREAK" or opCodeName == "NATIVECALL" then
						-- empty action for these
						registerAction(nil, nil, not options.ShowTrivialOperations)
					elseif opCodeName == "LOADNIL" then
						registerAction({A})
					elseif opCodeName == "LOADB" then -- load boolean
						registerAction({A}, {B, C})
					elseif opCodeName == "LOADN" then -- load number literal
						registerAction({A}, {sD})
					elseif opCodeName == "LOADK" then -- load constant
						registerAction({A}, {D})
					elseif opCodeName == "MOVE" then
						registerAction({A, B})
					elseif opCodeName == "GETGLOBAL" or opCodeName == "SETGLOBAL" then
						-- we most likely will not ever use C here.
						registerAction({A}, {aux}) --({A}, {C, aux})
					elseif opCodeName == "GETUPVAL" or opCodeName == "SETUPVAL" then
						registerAction({A}, {B})
					elseif opCodeName == "CLOSEUPVALS" then
						registerAction({A}, nil, not options.ShowTrivialOperations)
					elseif opCodeName == "GETIMPORT" then
						registerAction({A}, {D, aux})
					elseif opCodeName == "GETTABLE" or opCodeName == "SETTABLE" then
						registerAction({A, B, C})
					elseif opCodeName == "GETTABLEKS" or opCodeName == "SETTABLEKS" then
						registerAction({A, B}, {C, aux})
					elseif opCodeName == "GETTABLEN" or opCodeName == "SETTABLEN" then
						registerAction({A, B}, {C})
					elseif opCodeName == "NEWCLOSURE" then
						registerAction({A}, {D})

						local proto = innerProtos[D + 1]
						collectCaptures(index, proto)
						baseProto(proto)
					elseif opCodeName == "DUPCLOSURE" then
						registerAction({A}, {D})

						local proto = protoTable[constants[D + 1].value - 1]
						collectCaptures(index, proto)
						baseProto(proto)
					elseif opCodeName == "NAMECALL" then -- must be followed by CALL
						registerAction({A, B}, {C, aux}, not options.ShowTrivialOperations)
					elseif opCodeName == "CALL" then
						registerAction({A}, {B, C})
					elseif opCodeName == "RETURN" then
						registerAction({A}, {B})
					elseif opCodeName == "JUMP" or opCodeName == "JUMPBACK" then
						registerAction({}, {sD})
					elseif opCodeName == "JUMPIF" or opCodeName == "JUMPIFNOT" then
						registerAction({A}, {sD})
					elseif
						opCodeName == "JUMPIFEQ" or opCodeName == "JUMPIFLE" or opCodeName == "JUMPIFLT" or
						opCodeName == "JUMPIFNOTEQ" or opCodeName == "JUMPIFNOTLE" or opCodeName == "JUMPIFNOTLT"
					then
						registerAction({A, aux}, {sD})
					elseif
						opCodeName == "ADD" or opCodeName == "SUB" or opCodeName == "MUL" or
						opCodeName == "DIV" or opCodeName == "MOD" or opCodeName == "POW"
					then
						registerAction({A, B, C})
					elseif
						opCodeName == "ADDK" or opCodeName == "SUBK" or opCodeName == "MULK" or
						opCodeName == "DIVK" or opCodeName == "MODK" or opCodeName == "POWK"
					then
						registerAction({A, B}, {C})
					elseif opCodeName == "AND" or opCodeName == "OR" then
						registerAction({A, B, C})
					elseif opCodeName == "ANDK" or opCodeName == "ORK" then
						registerAction({A, B}, {C})
					elseif opCodeName == "CONCAT" then
						local registers = {A}
						for reg = B, C do
							table.insert(registers, reg)
						end
						registerAction(registers)
					elseif opCodeName == "NOT" or opCodeName == "MINUS" or opCodeName == "LENGTH" then
						registerAction({A, B})
					elseif opCodeName == "NEWTABLE" then
						registerAction({A}, {B, aux})
					elseif opCodeName == "DUPTABLE" then
						registerAction({A}, {D})
					elseif opCodeName == "SETLIST" then
						if C ~= 0 then
							local registers = {A, B}
							for i = 1, C - 2 do -- account for target and source registers
								table.insert(registers, A + i)
							end
							registerAction(registers, {aux, C})
						else
							registerAction({A, B}, {aux, C})
						end
					elseif opCodeName == "FORNPREP" then
						registerAction({A, A+1, A+2}, {sD})
					elseif opCodeName == "FORNLOOP" then
						registerAction({A}, {sD})
					elseif opCodeName == "FORGLOOP" then
						local numVariableRegisters = bit32.band(aux, 0xFF)

						local registers = {}
						for regIndex = 1, numVariableRegisters do
							table.insert(registers, A + regIndex)
						end
						registerAction(registers, {sD, aux})
					elseif opCodeName == "FORGPREP_INEXT" or opCodeName == "FORGPREP_NEXT" then
						registerAction({A, A+1})
					elseif opCodeName == "FORGPREP" then
						registerAction({A}, {sD})
					elseif opCodeName == "GETVARARGS" then
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
					elseif opCodeName == "PREPVARARGS" then
						registerAction({}, {A}, not options.ShowTrivialOperations)
					elseif opCodeName == "LOADKX" then
						registerAction({A}, {aux})
					elseif opCodeName == "JUMPX" then
						registerAction({}, {E})
					elseif opCodeName == "COVERAGE" then
						registerAction({}, {E}, not options.ShowTrivialOperations)
					elseif
						opCodeName == "JUMPXEQKNIL" or opCodeName == "JUMPXEQKB" or
						opCodeName == "JUMPXEQKN" or opCodeName == "JUMPXEQKS"
					then
						registerAction({A}, {sD, aux})
					elseif opCodeName == "CAPTURE" then
						-- empty action here
						registerAction(nil, nil, not options.ShowTrivialOperations)
					elseif opCodeName == "SUBRK" or opCodeName == "DIVRK" then -- constant sub/div
						registerAction({A, C}, {B})
					elseif opCodeName == "IDIV" then -- floor division
						registerAction({A, B, C})
					elseif opCodeName == "IDIVK" then -- floor division with 1 constant argument
						registerAction({A, B}, {C})
					elseif opCodeName == "FASTCALL" then -- reads info from the CALL instruction
						registerAction({}, {A, C}, not options.ShowTrivialOperations)
					elseif opCodeName == "FASTCALL1" then -- 1 register argument
						registerAction({B}, {A, C}, not options.ShowTrivialOperations)
					elseif opCodeName == "FASTCALL2" then -- 2 register arguments
						local sourceArgumentRegister2 = bit32.band(aux, 0xFF)

						registerAction({B, sourceArgumentRegister2}, {A, C}, not options.ShowTrivialOperations)
					elseif opCodeName == "FASTCALL2K" then -- 1 register argument and 1 constant argument
						registerAction({B}, {A, C, aux}, not options.ShowTrivialOperations)
					elseif opCodeName == "FASTCALL3" then
						local sourceArgumentRegister2 = bit32.band(aux, 0xFF)
						local sourceArgumentRegister3 = bit32.rshift(sourceArgumentRegister2, 8)

						registerAction({B, sourceArgumentRegister2, sourceArgumentRegister3}, {A, C}, not options.ShowTrivialOperations)
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

			if options.ListUsedGlobals and #usedGlobals > 0 then
				embed ..= string.format(Strings.USED_GLOBALS, table.concat(usedGlobals, ", "))
			end

			return embed .. result
		end

		-- now proceed based off mode
        if options.DecompilerMode == "disasm" then
        local lines = {}
        local indentLevel = 0

        local function indent()
        return string.rep("    ", indentLevel)
    end

        for line in result:gmatch("[^\r\n]+") do
        local clean = line:gsub("^%s+", ""):gsub("%s+$", "") -- trim
        if clean:match("^end") or clean:match("^else") then
            indentLevel = indentLevel - 1
        end

        table.insert(lines, indent() .. clean)

         if clean:match("^if ") or clean:match("^for ") or clean:match("^while ") or clean:match(" then$") or clean:match("^function") then
            indentLevel = indentLevel + 1
        elseif clean:match("^end$") then
            -- keep current indent
       end
   end

    return table.concat(lines, "\n")
end

	local function manager(proceed, issue)
		if proceed then
			local startTime
			local elapsedTime

			local result

			local function process()
				startTime = os.clock()
				result = finalize(organize())
				elapsedTime = os.clock() - startTime
			end
			task.spawn(process)

			-- I wish we could use coroutine.yield here
			while not result and (os.clock() - startTime) < options.DecompilerTimeout do
				task.wait()
			end

			if result then
				return string.format(Strings.SUCCESS, result), elapsedTime
			end

			return Strings.TIMEOUT
		else
			if issue == "COMPILATION_FAILURE" then
				local errorMessageLength = reader:len() - 1
				local errorMessage = reader:nextString(errorMessageLength)
				return string.format(Strings.COMPILATION_FAILURE, errorMessage)
			elseif issue == "UNSUPPORTED_LBC_VERSION" then
				return Strings.UNSUPPORTED_LBC_VERSION
			end
		end
	end

	bytecodeVersion = reader:nextByte()

	if bytecodeVersion == 0 then
		-- script errored
		return manager(false, "COMPILATION_FAILURE")
	elseif bytecodeVersion <= LuauBytecodeTag.LBC_VERSION_MAX and bytecodeVersion >= LuauBytecodeTag.LBC_VERSION_MIN then
		-- script uses supported bytecode version
		return manager(true)
	else
		return manager(false, "UNSUPPORTED_LBC_VERSION")
	end
end

local _ENV = (getgenv or getrenv or getfenv)()
_ENV.decompile = function(script, x, ...)
	if not getscriptbytecode then
		error("decompile is not enabled. (getscriptbytecode is missing)", 2)
		return
	end

	if typeof(script) ~= "Instance" then
		error("invalid argument #1 to 'decompile' (Instance expected)", 2)
		return
	end

	local function isScriptValid()
		local class = script.ClassName
		if class == "Script" then
			return script.RunContext == Enum.RunContext.Client
		else
			return class == "LocalScript" or class == "ModuleScript"
		end
	end
	if not isScriptValid() then
		error("invalid argument #1 to 'decompile' (Instance<LocalScript, ModuleScript> expected)", 2)
		return
	end

	local success, result = pcall(getscriptbytecode, script)
	if not success or type(result) ~= "string" then
		error(`decompile failed to grab script bytecode: {tostring(result)}`, 2)
		return
	end

	local options
	if x then
		options = table.clone(DEFAULT_OPTIONS)

		local varType = type(x)
		if varType == "table" then -- a dictionary of options
			for k, v in x do
				options[k] = v
			end
		elseif varType == "string" then -- mode
			options.DecompilerMode = x

			local timeout = ...
			if timeout then
				if type(timeout) ~= "number" then
					error("invalid argument #3 to 'decompile' (number expected)", 2)
				end

				options.DecompilerTimeout = timeout
			end
		else
			error("invalid argument #2 to 'decompile' (table/string expected)", 2)
		end
	else
		options = DEFAULT_OPTIONS
	end

	local output, elapsedTime = Decompile(result, options)

	if options.ReturnElapsedTime then
		return output, elapsedTime
	else
		return output
	end
end
