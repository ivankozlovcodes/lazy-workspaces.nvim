-- Nested neighbor spec (no init.lua): spec-named dir alongside workspace inside a container.
-- lua/
--   nvgoog/
--     default/    ← workspace
--     plugins/    ← neighbor spec dir (individual file loading)
local M = {}

M.WS         = "nvgoog/default"
M.SPEC_DIR   = "plugins"
M.SPEC_COUNT = 1
M.opts       = { specs = { "plugins" } }

M.tree = {
	["lua/nvgoog/default/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	["lua/nvgoog/default/file.lua"] = "-- config",
	["lua/nvgoog/plugins/file.lua"] = "return { 'foo/bar' }",
}

return M
