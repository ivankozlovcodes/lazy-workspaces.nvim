-- nvgoog case 3: dir at root has init.lua AND is named in specs.
-- plugins/ has init.lua that returns a spec; specs mentions "plugins".
-- Expected: plugins/ is a neighbor spec dir (loaded via init.lua), NOT a workspace.
-- default/ is a workspace. util/ ignored.
local M = {}

M.WS         = "default"
M.SPEC_DIR   = "plugins"
-- SPEC_COUNT = 1: only init.lua should be loaded (not individual sibling files).
-- file.lua also returns a spec so the count distinguishes init-only from all-files loading.
M.SPEC_COUNT = 1
M.opts       = { specs = { "plugins" } }

M.tree = {
	["lua/default/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/default/file.lua"] = "-- config",
	["lua/plugins/init.lua"] = "return { 'foo/bar' }",
	["lua/plugins/file.lua"] = "return { 'baz/qux' }",
	["lua/util/file.lua"]    = "-- util",
}

return M
