-- Container pattern: lua/group/ has no init.lua; children do.
-- Workspace keys use slash-separated paths: "group/common", "group/personal".
local M = {}

M.WS_COMMON   = "group/common"
M.WS_PERSONAL = "group/personal"
M.SPEC_COUNT  = 2

M.tree = {
	["lua/group/common/init.lua"]           = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/group/common/plugins/alpha.lua"]  = "return { 'a/alpha' }",
	["lua/group/personal/init.lua"]         = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/group/personal/plugins/beta.lua"] = "return { 'b/beta' }",
}

return M
