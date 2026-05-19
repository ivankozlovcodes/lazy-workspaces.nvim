-- Two sibling workspaces under the same config root.
local M = {}

M.WS_A       = "ws_a"
M.WS_B       = "ws_b"
M.SPEC_COUNT = 2

M.tree = {
	["lua/ws_a/init.lua"]          = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/ws_a/plugins/alpha.lua"] = "return { 'a/alpha' }",
	["lua/ws_b/init.lua"]          = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/ws_b/plugins/beta.lua"]  = "return { 'b/beta' }",
}

return M
