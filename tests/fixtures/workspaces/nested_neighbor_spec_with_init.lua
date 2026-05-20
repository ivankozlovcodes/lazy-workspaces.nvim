-- Nested neighbor spec (with init.lua): spec-named dir alongside workspace inside a container.
-- lua/
--   nvgoog/
--     default/    ← workspace
--     plugins/
--       init.lua  ← spec loaded via init.lua (file.lua is NOT loaded separately)
local M = {}

M.WS         = "nvgoog/default"
M.SPEC_DIR   = "plugins"
M.SPEC_COUNT = 1
M.opts       = { specs = { "plugins" } }

M.tree = {
	["lua/nvgoog/default/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/nvgoog/plugins/init.lua"] = "return { 'foo/bar' }",
	["lua/nvgoog/plugins/file.lua"] = "return { 'baz/qux' }",
}

return M
