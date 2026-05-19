-- nvgoog case 1: spec-named neighbor dir at root has no init.lua.
-- plugins/ has lua files but no init.lua, named in specs.
-- Expected: plugins/ individual .lua files ARE loaded as specs (individual file loading).
-- util/ is not named in specs → ignored. default/ is a workspace.
local M = {}

M.WS         = "default"
M.SPEC_DIR   = "plugins"
M.SPEC_COUNT = 1
M.opts       = { specs = { "plugins" } }

M.tree = {
	["lua/default/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/default/file.lua"] = "-- config",
	["lua/plugins/file.lua"] = "return { 'foo/bar' }",
	["lua/util/file.lua"]    = "-- util",
}

return M
