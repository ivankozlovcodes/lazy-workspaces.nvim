-- Workspace using a non-standard spec directory ("lazy/" instead of "plugins/").
local M = {}

M.WS         = "ws"
M.SPEC_DIR   = "lazy"
M.SPEC_COUNT = 1
M.opts       = { specs = { "lazy" } }

M.tree = {
	["lua/ws/init.lua"]     = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/ws/lazy/foo.lua"] = "return { 'foo/bar' }",
}

return M
