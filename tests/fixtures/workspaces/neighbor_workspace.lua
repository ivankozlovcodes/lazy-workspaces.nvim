-- nvgoog case 2: dir at root has init.lua but is NOT named in specs.
-- plugins/ has init.lua; specs only mentions "potato" (absent from lua/).
-- Expected: default/ and plugins/ are both workspaces. util/ ignored.
local M = {}

M.WS_DEFAULT = "default"
M.WS_PLUGINS = "plugins"
M.SPEC_DIR   = "potato"
M.opts       = { specs = { "potato" } }

M.tree = {
	["lua/default/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/default/file.lua"] = "-- config",
	["lua/plugins/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/plugins/file.lua"] = "-- plugin config",
	["lua/util/file.lua"]    = "-- util",
}

return M
