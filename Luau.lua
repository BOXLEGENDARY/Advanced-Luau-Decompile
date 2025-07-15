-- https://github.com/luau-lang/luau/raw/master/Common/include/Luau/Bytecode.h

local CASE_MULTIPLIER = 227 -- 0xE3

-- Common constants and optimized bitwise function references
-- These improve performance by reducing repeated global lookups
local bit32_band = bit32.band         -- Bitwise AND
local bit32_rshift = bit32.rshift     -- Bitwise right shift
local bit32_lshift = bit32.lshift     -- Bitwise left shift
local bit32_bnot = bit32.bnot         -- Bitwise NOT

-- Frequently used bitmask constants and shift values for decompile instructions
local OPCODE_MASK = 0xFF              -- Mask to extract the opcode from instruction
local SHIFT_8 = 8                     -- Bit shift for A field
local SHIFT_16 = 16                   -- Bit shift for B/D field
local SHIFT_24 = 24                   -- Bit shift for C field
local MAX_15BIT = 0x7FFF              -- Max value for signed 15-bit
local MAX_16BIT = 0xFFFF              -- Max for unsigned 16-bit

local Luau = {
	OpCode = {
		{ ["name"] = "NOP", ["type"] = "none" },
		{ ["name"] = "BREAK", ["type"] = "none" },
		{ ["name"] = "LOADNIL", ["type"] = "A" },
		{ ["name"] = "LOADB", ["type"] = "ABC" },
		{ ["name"] = "LOADN", ["type"] = "AsD" },
		{ ["name"] = "LOADK", ["type"] = "AD" },
		{ ["name"] = "MOVE", ["type"] = "AB" },
		{ ["name"] = "GETGLOBAL", ["type"] = "AC", ["aux"] = true },
		{ ["name"] = "SETGLOBAL", ["type"] = "AC", ["aux"] = true },
		{ ["name"] = "GETUPVAL", ["type"] = "AB" },
		{ ["name"] = "SETUPVAL", ["type"] = "AB" },
		{ ["name"] = "CLOSEUPVALS", ["type"] = "A" },
		{ ["name"] = "GETIMPORT", ["type"] = "AD", ["aux"] = true },		
		{ ["name"] = "GETTABLE", ["type"] = "ABC" },
		{ ["name"] = "SETTABLE", ["type"] = "ABC" },
		{ ["name"] = "GETTABLEKS", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "SETTABLEKS", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "GETTABLEN", ["type"] = "ABC" },
		{ ["name"] = "SETTABLEN", ["type"] = "ABC" },
		{ ["name"] = "NEWCLOSURE", ["type"] = "AD" },
		{ ["name"] = "NAMECALL", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "CALL", ["type"] = "ABC" },
		{ ["name"] = "RETURN", ["type"] = "AB" },
		{ ["name"] = "JUMP", ["type"] = "sD" },
		{ ["name"] = "JUMPBACK", ["type"] = "sD" },
		{ ["name"] = "JUMPIF", ["type"] = "AsD" },
		{ ["name"] = "JUMPIFNOT", ["type"] = "AsD" },
		{ ["name"] = "JUMPIFEQ", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPIFLE", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPIFLT", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPIFNOTEQ", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPIFNOTLE", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPIFNOTLT", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "ADD", ["type"] = "ABC" },
		{ ["name"] = "SUB", ["type"] = "ABC" },
		{ ["name"] = "MUL", ["type"] = "ABC" },
		{ ["name"] = "DIV", ["type"] = "ABC" },
		{ ["name"] = "MOD", ["type"] = "ABC" },
		{ ["name"] = "POW", ["type"] = "ABC" },
		{ ["name"] = "ADDK", ["type"] = "ABC" },
		{ ["name"] = "SUBK", ["type"] = "ABC" },
		{ ["name"] = "MULK", ["type"] = "ABC" },
		{ ["name"] = "DIVK", ["type"] = "ABC" },
		{ ["name"] = "MODK", ["type"] = "ABC" },
		{ ["name"] = "POWK", ["type"] = "ABC" },
		{ ["name"] = "AND", ["type"] = "ABC" },
		{ ["name"] = "OR", ["type"] = "ABC" },
		{ ["name"] = "ANDK", ["type"] = "ABC" },
		{ ["name"] = "ORK", ["type"] = "ABC" },
		{ ["name"] = "CONCAT", ["type"] = "ABC" },
		{ ["name"] = "NOT", ["type"] = "AB" },
		{ ["name"] = "MINUS", ["type"] = "AB" },
		{ ["name"] = "LENGTH", ["type"] = "AB" },
		{ ["name"] = "NEWTABLE", ["type"] = "AB", ["aux"] = true },
		{ ["name"] = "DUPTABLE", ["type"] = "AD" },
		{ ["name"] = "SETLIST", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "FORNPREP", ["type"] = "AsD" },
		{ ["name"] = "FORNLOOP", ["type"] = "AsD" },
		{ ["name"] = "FORGLOOP", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "FORGPREP_INEXT", ["type"] = "A" },
		{ ["name"] = "FASTCALL3", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "FORGPREP_NEXT", ["type"] = "A" },
		{ ["name"] = "NATIVECALL", ["type"] = "none" },
		{ ["name"] = "GETVARARGS", ["type"] = "AB" },
		{ ["name"] = "DUPCLOSURE", ["type"] = "AD" },
		{ ["name"] = "PREPVARARGS", ["type"] = "A" },
		{ ["name"] = "LOADKX", ["type"] = "A", ["aux"] = true },
		{ ["name"] = "JUMPX", ["type"] = "E" },
		{ ["name"] = "FASTCALL", ["type"] = "AC" },
		{ ["name"] = "COVERAGE", ["type"] = "E" },
		{ ["name"] = "CAPTURE", ["type"] = "AB" },
		{ ["name"] = "SUBRK", ["type"] = "ABC" },
		{ ["name"] = "DIVRK", ["type"] = "ABC" },
		{ ["name"] = "FASTCALL1", ["type"] = "ABC" },
		{ ["name"] = "FASTCALL2", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "FASTCALL2K", ["type"] = "ABC", ["aux"] = true },
		{ ["name"] = "FORGPREP", ["type"] = "AsD" },
		{ ["name"] = "JUMPXEQKNIL", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPXEQKB", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPXEQKN", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "JUMPXEQKS", ["type"] = "AsD", ["aux"] = true },
		{ ["name"] = "IDIV", ["type"] = "ABC" },
		{ ["name"] = "IDIVK", ["type"] = "ABC" },
		{ ["name"] = "_COUNT", ["type"] = "none" }
	},
	-- Bytecode tags, used internally for bytecode encoded as a string
	BytecodeTag = {
		-- Bytecode version; runtime supports [MIN, MAX]
		LBC_VERSION_MIN = 3,
		LBC_VERSION_MAX = 6,
		-- Type encoding version
		LBC_TYPE_VERSION_MIN = 1,
		LBC_TYPE_VERSION_MAX = 3,
		-- Types of constant table entries
		LBC_CONSTANT_NIL = 0,
		LBC_CONSTANT_BOOLEAN = 1,
		LBC_CONSTANT_NUMBER = 2,
		LBC_CONSTANT_STRING = 3,
		LBC_CONSTANT_IMPORT = 4,
		LBC_CONSTANT_TABLE = 5,
		LBC_CONSTANT_CLOSURE = 6,
		LBC_CONSTANT_VECTOR = 7
	},
	-- Type table tags
	BytecodeType = {
		LBC_TYPE_NIL = 0,
		LBC_TYPE_BOOLEAN = 1,
		LBC_TYPE_NUMBER = 2,
		LBC_TYPE_STRING = 3,
		LBC_TYPE_TABLE = 4,
		LBC_TYPE_FUNCTION = 5,
		LBC_TYPE_THREAD = 6,
		LBC_TYPE_USERDATA = 7,
		LBC_TYPE_VECTOR = 8,
		LBC_TYPE_BUFFER = 9,

		LBC_TYPE_ANY = 15,

		LBC_TYPE_TAGGED_USERDATA_BASE = 64,
		LBC_TYPE_TAGGED_USERDATA_END = 64 + 32,

		LBC_TYPE_OPTIONAL_BIT = bit32.lshift(1, 7), -- 128

		LBC_TYPE_INVALID = 256
	},
	-- Capture type, used in LOP_CAPTURE
	CaptureType = {
		LCT_VAL = 0,
		LCT_REF = 1,
		LCT_UPVAL = 2
	},
	-- Builtin function ids, used in LOP_FASTCALL
	BuiltinFunction = {
		LBF_NONE = 0,

		-- assert()
		LBF_ASSERT = 1,

		-- math.
		LBF_MATH_ABS = 2,
		LBF_MATH_ACOS = 3,
		LBF_MATH_ASIN = 4,
		LBF_MATH_ATAN2 = 5,
		LBF_MATH_ATAN = 6,
		LBF_MATH_CEIL = 7,
		LBF_MATH_COSH = 8,
		LBF_MATH_COS = 9,
		LBF_MATH_DEG = 10,
		LBF_MATH_EXP = 11,
		LBF_MATH_FLOOR = 12,
		LBF_MATH_FMOD = 13,
		LBF_MATH_FREXP = 14,
		LBF_MATH_LDEXP = 15,
		LBF_MATH_LOG10 = 16,
		LBF_MATH_LOG = 17,
		LBF_MATH_MAX = 18,
		LBF_MATH_MIN = 19,
		LBF_MATH_MODF = 20,
		LBF_MATH_POW = 21,
		LBF_MATH_RAD = 22,
		LBF_MATH_SINH = 23,
		LBF_MATH_SIN = 24,
		LBF_MATH_SQRT = 25,
		LBF_MATH_TANH = 26,
		LBF_MATH_TAN = 27,

		-- bit32.
		LBF_BIT32_ARSHIFT = 28,
		LBF_BIT32_BAND = 29,
		LBF_BIT32_BNOT = 30,
		LBF_BIT32_BOR = 31,
		LBF_BIT32_BXOR = 32,
		LBF_BIT32_BTEST = 33,
		LBF_BIT32_EXTRACT = 34,
		LBF_BIT32_LROTATE = 35,
		LBF_BIT32_LSHIFT = 36,
		LBF_BIT32_REPLACE = 37,
		LBF_BIT32_RROTATE = 38,
		LBF_BIT32_RSHIFT = 39,

		-- type()
		LBF_TYPE = 40,

		-- string.
		LBF_STRING_BYTE = 41,
		LBF_STRING_CHAR = 42,
		LBF_STRING_LEN = 43,

		-- typeof()
		LBF_TYPEOF = 44,

		-- string.
		LBF_STRING_SUB = 45,

		-- math.
		LBF_MATH_CLAMP = 46,
		LBF_MATH_SIGN = 47,
		LBF_MATH_ROUND = 48,

		-- raw*
		LBF_RAWSET = 49,
		LBF_RAWGET = 50,
		LBF_RAWEQUAL = 51,

		-- table.
		LBF_TABLE_INSERT = 52,
		LBF_TABLE_UNPACK = 53,

		-- vector ctor
		LBF_VECTOR = 54,

		-- bit32.count
		LBF_BIT32_COUNTLZ = 55,
		LBF_BIT32_COUNTRZ = 56,

		-- select(_, ...)
		LBF_SELECT_VARARG = 57,

		-- rawlen
		LBF_RAWLEN = 58,

		-- bit32.extract(_, k, k)
		LBF_BIT32_EXTRACTK = 59,

		-- get/setmetatable
		LBF_GETMETATABLE = 60,
		LBF_SETMETATABLE = 61,

		-- tonumber/tostring
		LBF_TONUMBER = 62,
		LBF_TOSTRING = 63,

		-- bit32.byteswap(n)
		LBF_BIT32_BYTESWAP = 64,

		-- buffer.
		LBF_BUFFER_READI8 = 65,
		LBF_BUFFER_READU8 = 66,
		LBF_BUFFER_WRITEU8 = 67,
		LBF_BUFFER_READI16 = 68,
		LBF_BUFFER_READU16 = 69,
		LBF_BUFFER_WRITEU16 = 70,
		LBF_BUFFER_READI32 = 71,
		LBF_BUFFER_READU32 = 72,
		LBF_BUFFER_WRITEU32 = 73,
		LBF_BUFFER_READF32 = 74,
		LBF_BUFFER_WRITEF32 = 75,
		LBF_BUFFER_READF64 = 76,
		LBF_BUFFER_WRITEF64 = 77,

		-- vector.
		LBF_VECTOR_MAGNITUDE = 78,
		LBF_VECTOR_NORMALIZE = 79,
		LBF_VECTOR_CROSS = 80,
		LBF_VECTOR_DOT = 81,
		LBF_VECTOR_FLOOR = 82,
		LBF_VECTOR_CEIL = 83,
		LBF_VECTOR_ABS = 84,
		LBF_VECTOR_SIGN = 85,
		LBF_VECTOR_CLAMP = 86,
		LBF_VECTOR_MIN = 87,
		LBF_VECTOR_MAX = 88
	},
	-- Proto flag bitmask, stored in Proto::flags
	ProtoFlag = {
		-- used to tag main proto for modules with --!native
		LPF_NATIVE_MODULE = bit32.lshift(1, 0),
		-- used to tag individual protos as not profitable to compile natively
		LPF_NATIVE_COLD = bit32.lshift(1, 1),
		-- used to tag main proto for modules that have at least one function with native attribute
		LPF_NATIVE_FUNCTION = bit32.lshift(1, 2)
	}
}

-- Extract opcode (lower 8 bits of instruction)
function Luau:INSN_OP(insn)
	return bit32_band(insn, OPCODE_MASK)
end

-- Extract A field (next 8 bits after opcode)
function Luau:INSN_A(insn)
	return bit32_band(bit32_rshift(insn, SHIFT_8), 0xFF)
end
-- Extract B field (3rd byte in instruction)
function Luau:INSN_B(insn)
	return bit32_band(bit32_rshift(insn, SHIFT_16), 0xFF)
end
-- Extract C field (4th byte in instruction)
function Luau:INSN_C(insn)
	return bit32_band(bit32_rshift(insn, SHIFT_24), 0xFF)
end

-- Extract D field as signed 16-bit (two's complement)
function Luau:INSN_D(insn)
	return bit32_rshift(insn, SHIFT_16)
end
function Luau:INSN_sD(insn)
	local D = bit32_rshift(insn, SHIFT_16)
	if D > MAX_15BIT and D <= MAX_16BIT then
		return (-(MAX_16BIT - D)) - 1
	end
	return D
end

-- Extract E field (signed 24-bit field)
function Luau:INSN_E(insn)
	return bit32_rshift(insn, SHIFT_8)
end

-- Converts internal type bytecode tag to human-readable type name
-- Example: 2 => "number", 3 => "string", 2|128 => "number?"
function Luau:GetBaseTypeString(type, checkOptional)
    -- Strip off optional flag using bitwise NOT
	local tag = bit32_band(type, bit32_bnot(self.BytecodeType.LBC_TYPE_OPTIONAL_BIT))

    -- Lookup table for base types
	local map = {
		[0] = "nil", [1] = "boolean", [2] = "number", [3] = "string",
		[4] = "table", [5] = "function", [6] = "thread", [7] = "userdata",
		[8] = "Vector3", [9] = "buffer", [15] = "any"
	}

	-- Fail early if unknown type
	local result = map[tag]
	assert(result, "Unhandled type in GetBaseTypeString")

	-- Append '?' if optional type is present
	if checkOptional and bit32_band(type, self.BytecodeType.LBC_TYPE_OPTIONAL_BIT) ~= 0 then
		result = result .. "?"
	end

	return result
end
-- Map from Builtin Function ID to their string representation
-- Used when decompile fastcall or native builtins (like math.abs, bit32.bxor)
local builtinLookup = {
	[1] = "assert",
	[2] = "math.abs",  [3] = "math.acos", [4] = "math.asin", [5] = "math.atan2", [6] = "math.atan",
	[7] = "math.ceil", [8] = "math.cosh", [9] = "math.cos", [10] = "math.deg", [11] = "math.exp",
	[12] = "math.floor", [13] = "math.fmod", [14] = "math.frexp", [15] = "math.ldexp", [16] = "math.log10",
	[17] = "math.log", [18] = "math.max", [19] = "math.min", [20] = "math.modf", [21] = "math.pow",
	[22] = "math.rad", [23] = "math.sinh", [24] = "math.sin", [25] = "math.sqrt", [26] = "math.tanh", [27] = "math.tan",
	[28] = "bit32.arshift", [29] = "bit32.band", [30] = "bit32.bnot", [31] = "bit32.bor", [32] = "bit32.bxor",
	[33] = "bit32.btest", [34] = "bit32.extract", [35] = "bit32.lrotate", [36] = "bit32.lshift", [37] = "bit32.replace",
	[38] = "bit32.rrotate", [39] = "bit32.rshift",
	[40] = "type", [41] = "string.byte", [42] = "string.char", [43] = "string.len",
	[44] = "typeof", [45] = "string.sub", [46] = "math.clamp", [47] = "math.sign", [48] = "math.round",
	[49] = "rawset", [50] = "rawget", [51] = "rawequal", [52] = "table.insert", [53] = "table.unpack",
	[54] = "Vector3.new", [55] = "bit32.countlz", [56] = "bit32.countrz", [57] = "select",
	[58] = "rawlen", [59] = "bit32.extract", [60] = "getmetatable", [61] = "setmetatable",
	[62] = "tonumber", [63] = "tostring",
	[78] = "vector.magnitude", [79] = "vector.normalize", [80] = "vector.cross", [81] = "vector.dot",
	[82] = "vector.floor", [83] = "vector.ceil", [84] = "vector.abs", [85] = "vector.sign",
	[86] = "vector.clamp", [87] = "vector.min", [88] = "vector.max"
}

-- Convert builtin function ID to string (fallback to "none")
function Luau:GetBuiltinInfo(bfid)
	return builtinLookup[bfid] or "none"
end

-- Final transformation to optimize OpCode table:
-- Replaces indexed array [1..n] with a hashmap keyed by opcode case ID
local function prepare(t)
	local LuauOpCode = t.OpCode
	local optimized = {}

	-- Convert to a fast-case dispatch table using bit-masked keys
	for i = 1, #LuauOpCode do
		local v = LuauOpCode[i]
		local case = bit32_band((i - 1) * CASE_MULTIPLIER, 0xFF)
		optimized[case] = v
	end

	t.OpCode = optimized
	return t
end

return prepare(Luau)