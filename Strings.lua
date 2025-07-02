-- Collection of strings later formatted by the decompiler for output
local MemeStrings = {
	" Decompline By ZxL",
}

local Strings = {
	SUCCESS = "--" .. MemeStrings[math.random(#MemeStrings)] .. "\n%s",
	TIMEOUT = "-- DECOMPILER TIMEOUT",
	COMPILATION_FAILURE = "-- SCRIPT FAILED TO COMPILE, ERROR:\n%s",
	UNSUPPORTED_LBC_VERSION = "-- PASSED BYTECODE IS TOO OLD AND IS NOT SUPPORTED",
	USED_GLOBALS = "-- USED GLOBALS: %s.\n",
	DECOMPILER_REMARK = "-- DECOMPILER REMARK: %s\n"
}

return Strings