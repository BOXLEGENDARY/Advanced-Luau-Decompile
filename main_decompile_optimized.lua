-- ##################################################
-- 1. CONFIG
-- ##################################################
local DEFAULT_OPTIONS = {
    ReaderFloatPrecision = 7,
    DecompilerTimeout = 10,
    DecompilerMode = "disasm",
    EnabledRemarks = {
        ColdRemark = true,
        InlineRemark = false
    },
    ShowDebugInformation = true,
    ShowInstructionLines = true,
    ShowOperationIndex = true,
    ShowOperationNames = true,
    ShowTrivialOperations = false,
    UseTypeInfo = true,
    ListUsedGlobals = true,
    ReturnElapsedTime = false
}

-- ##################################################
-- 2. HELPERS
-- ##################################################
local function padLeft(str, char, len)
    str = tostring(str)
    while #str < len do str = char .. str end
    return str
end

local function padRight(str, char, len)
    str = tostring(str)
    while #str < len do str = str .. char end
    return str
end

local function toBoolean(x)
    return x == 1 or x == true
end

local function toEscapedString(value)
    if typeof(value) == "string" then
        return string.format("%q", value)
    elseif typeof(value) == "boolean" then
        return tostring(value)
    elseif typeof(value) == "number" then
        return tostring(value)
    end
    return "nil"
end

-- ##################################################
-- 3. URL LOADER
-- ##################################################
local function LoadFromUrl(moduleName)
    local BASE_USER = "BOXLEGENDARY"
    local BASE_BRANCH = "main"
    local url = string.format("https://raw.githubusercontent.com/%%s/ZDex/%%s/%%s.lua", BASE_USER, BASE_BRANCH, moduleName)

    local success, content = pcall(function()
        return game:HttpGet(url)
    end)
    if not success then
        warn("[!] Load Failed for module: " .. moduleName)
        return nil
    end

    local ok, result = pcall(loadstring, content)
    if not ok then
        warn("[!] loadstring failed for module: " .. moduleName)
        return nil
    end

    return result()
end

-- ##################################################
-- 4. FLAG MANAGER
-- ##################################################
local function LoadFlag(name)
    local ok, result = pcall(function()
        return game:GetFastFlag(name)
    end)
    return ok and result or true
end

-- ##################################################
-- 5. CORE SETUP (constant preload)
-- ##################################################
local Implementations = LoadFromUrl("Implementations")
local Reader = LoadFromUrl("Reader")
local Strings = LoadFromUrl("Strings")
local Luau = LoadFromUrl("Luau")

local LuauOpCode = Luau.OpCode
local LuauBytecodeTag = Luau.BytecodeTag
local LuauCaptureType = Luau.CaptureType
local LuauProtoFlag = Luau.ProtoFlag

local LuauCompileUserdataInfo = LoadFlag("LuauCompileUserdataInfo")

-- ##################################################
-- 6. MAIN DECOMPILE
-- ##################################################
local MainDecompiler = LoadFromUrl("main_decompile_optimized")

-- ##################################################
-- 7. ENTRY POINT
-- ##################################################
return function(bytecode, options)
    options = options or DEFAULT_OPTIONS
    Reader:Set(options.ReaderFloatPrecision or 7)
    return MainDecompiler(bytecode, options)
end
