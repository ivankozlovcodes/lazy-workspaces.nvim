local M = {}

M.WS         = "ws"
M.SPEC_COUNT = 2

M.tree = {
	["lua/ws/init.lua"]        = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/ws/plugins/foo.lua"] = "return { 'foo/bar', opts = {} }",
	["lua/ws/plugins/baz.lua"] = "return { 'baz/qux' }",
}

return M
