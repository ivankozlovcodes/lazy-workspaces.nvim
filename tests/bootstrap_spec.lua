local stub = require("luassert.stub")
local H = require("tests.helpers")
local bootstrap = require("lazy-workspaces.bootstrap")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function run_bootstrap(src, out)
	local confirm_stub = stub(vim.fn, "confirm")
	confirm_stub.returns(1)

	local notify_stub = stub(vim, "notify")

	bootstrap.command({ args = src .. " " .. out })

	confirm_stub:revert()
	notify_stub:revert()
end

-- ── johnnyjumper fixture ───────────────────────────────────────────────────────
-- Single namespace, lazy/ plugin dir, lazy_init.lua bootstrap file,
-- plus a lua/user/ subfolder with no init.lua (must NOT be detected as namespace)

describe("fixture: johnnyjumper", function()
	local src, out

	before_each(function()
		src = H.make_tree({
			["init.lua"]                       = "require('johnnyjumper')",
			["lua/johnnyjumper/init.lua"]      = "require('johnnyjumper.lazy_init')\nrequire('johnnyjumper.set')\nrequire('johnnyjumper.remap')\nrequire('johnnyjumper.autocmd')",
			["lua/johnnyjumper/lazy_init.lua"] = 'require("lazy").setup({})',
			["lua/johnnyjumper/lazy/init.lua"] = "return {}",
			["lua/user/vscode_keymaps.lua"]    = "-- vscode",
		})
		out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		run_bootstrap(src, out)
	end)

	after_each(function()
		H.cleanup(src)
		H.cleanup(out)
	end)

	describe("namespace detection", function()
		it("detects johnnyjumper namespace", function()
			assert.is_true(H.dir_exists(out .. "/lua/johnnyjumper"))
		end)

		it("does not treat lua/user/ as namespace (no init.lua)", function()
			-- user/ is copied but its files are not transformed
			assert.is_true(H.file_exists(out .. "/lua/user/vscode_keymaps.lua"))
			-- no M.setup wrapping applied to user namespace
			assert.is_false(H.content_has(out .. "/lua/user/vscode_keymaps.lua", "function M%.setup"))
		end)
	end)

	describe("spec dir detection", function()
		it("keeps lazy/ dir in place (no rename)", function()
			assert.is_true(H.dir_exists(out .. "/lua/johnnyjumper/lazy"))
		end)

		it("includes lazy in generated specs opt", function()
			assert.is_true(H.content_has(out .. "/init.lua", '"lazy"'))
		end)
	end)

	describe("namespace init.lua transformation", function()
		local init_path

		before_each(function()
			init_path = out .. "/lua/johnnyjumper/init.lua"
		end)

		it("wraps content in M.setup()", function()
			assert.is_true(H.content_has(init_path, "function M%.setup"))
		end)

		it("adds return M", function()
			assert.is_true(H.content_has(init_path, "^return M$"))
		end)

		it("strips lazy_init require", function()
			assert.is_true(H.content_lacks(init_path, 'require%("johnnyjumper%.lazy_init"%)'))
		end)

		it("preserves other requires", function()
			assert.is_true(H.content_has(init_path, "johnnyjumper%.set"))
			assert.is_true(H.content_has(init_path, "johnnyjumper%.remap"))
			assert.is_true(H.content_has(init_path, "johnnyjumper%.autocmd"))
		end)
	end)

	describe("lazy bootstrap file disabled", function()
		it("renames lazy_init.lua to .bak", function()
			assert.is_true(H.file_exists(out .. "/lua/johnnyjumper/lazy_init.lua.bak"))
		end)

		it("removes original lazy_init.lua", function()
			assert.is_false(H.file_exists(out .. "/lua/johnnyjumper/lazy_init.lua"))
		end)

		it("bak file retains original content", function()
			assert.is_true(H.content_has(out .. "/lua/johnnyjumper/lazy_init.lua.bak", 'require%("lazy"%)%.setup'))
		end)
	end)

	describe("generated root init.lua", function()
		local init_path

		before_each(function()
			init_path = out .. "/init.lua"
		end)

		it("creates init.lua at output root", function()
			assert.is_true(H.file_exists(init_path))
		end)

		it("includes configs key", function()
			assert.is_true(H.content_has(init_path, "configs"))
		end)

		it("bootstraps lazy-workspaces", function()
			assert.is_true(H.content_has(init_path, "lazy%-workspaces"))
		end)

		it("calls lazy-workspaces setup", function()
			assert.is_true(H.content_has(init_path, 'require%("lazy%-workspaces"%)%.setup'))
		end)

		it("does not call lazy.setup directly", function()
			assert.is_true(H.content_lacks(init_path, 'require%("lazy"%)%.setup'))
		end)

		it("does not call collect directly", function()
			assert.is_true(H.content_lacks(init_path, "%.collect%("))
		end)

		it("sets workspace_root to output dir", function()
			assert.is_true(H.content_has(init_path, vim.pesc(out)))
		end)
	end)
end)

-- ── fixture: nested namespaces (container pattern) ───────────────────────────
-- lua/myconfig/ has no init.lua → container
-- lua/myconfig/common/ and lua/myconfig/personal/ have init.lua → workspaces

describe("fixture: nested namespaces", function()
	local src, out

	before_each(function()
		src = H.make_tree({
			["init.lua"]                                    = "require('myconfig.common')",
			["lua/myconfig/common/init.lua"]                = "require('myconfig.common.lazy_init')\nrequire('myconfig.common.set')",
			["lua/myconfig/common/lazy_init.lua"]           = 'require("lazy").setup({})',
			["lua/myconfig/common/lazy/init.lua"]           = "return {}",
			["lua/myconfig/common/lazy/some_plugin.lua"]    = "return { 'author/some_plugin', opts = {} }",
			["lua/myconfig/personal/init.lua"]              = "require('myconfig.personal.set')",
		})
		out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		run_bootstrap(src, out)
	end)

	after_each(function()
		H.cleanup(src)
		H.cleanup(out)
	end)

	describe("namespace detection", function()
		it("creates output dir for myconfig/common", function()
			assert.is_true(H.dir_exists(out .. "/lua/myconfig/common"))
		end)

		it("creates output dir for myconfig/personal", function()
			assert.is_true(H.dir_exists(out .. "/lua/myconfig/personal"))
		end)
	end)

	describe("generated root init.lua", function()
		local init_path

		before_each(function()
			init_path = out .. "/init.lua"
		end)

		it("includes configs key", function()
			assert.is_true(H.content_has(init_path, "configs"))
		end)

		it("includes workspace url with out_dir path", function()
			assert.is_true(H.content_has(init_path, vim.pesc(out)))
		end)
	end)

	describe("namespace init.lua transformation", function()
		it("wraps myconfig/common/init.lua in M.setup()", function()
			assert.is_true(H.content_has(out .. "/lua/myconfig/common/init.lua", "function M%.setup"))
		end)

		it("wraps myconfig/personal/init.lua in M.setup()", function()
			assert.is_true(H.content_has(out .. "/lua/myconfig/personal/init.lua", "function M%.setup"))
		end)

		it("strips lazy_init require from common/init.lua", function()
			assert.is_true(H.content_lacks(out .. "/lua/myconfig/common/init.lua", "lazy_init"))
		end)
	end)

	describe("spec dir detection", function()
		it("keeps lazy/ dir in place (no rename)", function()
			assert.is_true(H.dir_exists(out .. "/lua/myconfig/common/lazy"))
		end)

		it("preserves some_plugin.lua inside lazy/", function()
			assert.is_true(H.file_exists(out .. "/lua/myconfig/common/lazy/some_plugin.lua"))
		end)

		it("includes lazy in generated specs opt", function()
			assert.is_true(H.content_has(out .. "/init.lua", '"lazy"'))
		end)
	end)

	describe("lazy bootstrap file disabled", function()
		it("renames lazy_init.lua to .bak in myconfig/common/", function()
			assert.is_true(H.file_exists(out .. "/lua/myconfig/common/lazy_init.lua.bak"))
		end)

		it("removes original lazy_init.lua from myconfig/common/", function()
			assert.is_false(H.file_exists(out .. "/lua/myconfig/common/lazy_init.lua"))
		end)
	end)
end)

-- ── fixture: extra spec dirs (themes/ alongside plugins/) ────────────────────
-- Mirrors ~/git/nvim.conf.d: myconfig/common has both plugins/ and themes/.
-- Bootstrap should detect themes/ and emit specs = { "plugins", "themes" } in init.lua.

describe("fixture: extra spec dirs", function()
	local src, out

	before_each(function()
		src = H.make_tree({
			["lua/myconfig/common/init.lua"]                   = "local M = {}\nfunction M.setup() end\nreturn M",
			["lua/myconfig/common/plugins/some_plugin.lua"]    = "return { 'author/some_plugin' }",
			["lua/myconfig/common/themes/kanagawa.lua"]        = "return { 'rebelot/kanagawa.nvim' }",
			["lua/myconfig/personal/init.lua"]                 = "local M = {}\nfunction M.setup() end\nreturn M",
		})
		out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		run_bootstrap(src, out)
	end)

	after_each(function()
		H.cleanup(src)
		H.cleanup(out)
	end)

	it("includes specs with both plugins and themes in generated init.lua", function()
		assert.is_true(H.content_has(out .. "/init.lua", '"plugins"'))
		assert.is_true(H.content_has(out .. "/init.lua", '"themes"'))
	end)

	it("does not emit specs line when only plugins/ present", function()
		local src2 = H.make_tree({
			["lua/myconfig/common/init.lua"]                = "local M = {}\nfunction M.setup() end\nreturn M",
			["lua/myconfig/common/plugins/foo.lua"]         = "return { 'a/b' }",
		})
		local out2 = vim.fn.tempname()
		vim.fn.mkdir(out2, "p")
		run_bootstrap(src2, out2)
		assert.is_true(H.content_lacks(out2 .. "/init.lua", "specs"))
		H.cleanup(src2)
		H.cleanup(out2)
	end)
end)

-- ── fixture: flat config (plugins/ + config/) ────────────────────────────────
-- No namespace init.lua anywhere — detect_namespaces returns empty.
-- Bootstrap falls back to flat migration: plugins/ + config/ become workspaces.

describe("fixture: flat config", function()
	local src, out

	before_each(function()
		src = H.make_tree({
			["init.lua"]                    = 'require("lazy").setup({})',
			["lua/plugins/whichkey.lua"]    = 'return { "folke/which-key.nvim" }',
			["lua/plugins/treesitter.lua"]  = 'return { "nvim-treesitter/nvim-treesitter" }',
			["lua/config/options.lua"]      = "vim.opt.number = true",
			["lua/config/keymaps.lua"]      = "vim.keymap.set('n', 'q', '<cmd>q<cr>')",
		})
		out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		run_bootstrap(src, out)
	end)

	after_each(function()
		H.cleanup(src)
		H.cleanup(out)
	end)

	describe("plugins workspace", function()
		it("moves specs into plugins/plugins/", function()
			assert.is_true(H.file_exists(out .. "/lua/plugins/plugins/whichkey.lua"))
			assert.is_true(H.file_exists(out .. "/lua/plugins/plugins/treesitter.lua"))
		end)

		it("removes specs from plugins/ root", function()
			assert.is_false(H.file_exists(out .. "/lua/plugins/whichkey.lua"))
			assert.is_false(H.file_exists(out .. "/lua/plugins/treesitter.lua"))
		end)

		it("generates plugins/init.lua", function()
			assert.is_true(H.file_exists(out .. "/lua/plugins/init.lua"))
		end)

		it("plugins/init.lua has empty M.setup()", function()
			assert.is_true(H.content_has(out .. "/lua/plugins/init.lua", "function M%.setup"))
		end)
	end)

	describe("config workspace", function()
		it("generates config/init.lua", function()
			assert.is_true(H.file_exists(out .. "/lua/config/init.lua"))
		end)

		it("config/init.lua requires each config file", function()
			assert.is_true(H.content_has(out .. "/lua/config/init.lua", 'require%("config%.options"%)'))
			assert.is_true(H.content_has(out .. "/lua/config/init.lua", 'require%("config%.keymaps"%)'))
		end)

		it("config/init.lua wraps in M.setup()", function()
			assert.is_true(H.content_has(out .. "/lua/config/init.lua", "function M%.setup"))
			assert.is_true(H.content_has(out .. "/lua/config/init.lua", "^return M$"))
		end)

		it("leaves config files in place", function()
			assert.is_true(H.file_exists(out .. "/lua/config/options.lua"))
			assert.is_true(H.file_exists(out .. "/lua/config/keymaps.lua"))
		end)
	end)

	describe("root init.lua", function()
		it("backs up original init.lua", function()
			assert.is_true(H.file_exists(out .. "/init.lua.bak"))
		end)

		it("generates new root init.lua", function()
			assert.is_true(H.file_exists(out .. "/init.lua"))
		end)

		it("includes configs key", function()
			assert.is_true(H.content_has(out .. "/init.lua", "configs"))
		end)

		it("includes workspace url with out_dir path", function()
			assert.is_true(H.content_has(out .. "/init.lua", vim.pesc(out)))
		end)

		it("bak file did not use lazy-workspaces", function()
			assert.is_true(H.content_lacks(out .. "/init.lua.bak", "lazy%-workspaces"))
		end)

		it("new init.lua calls lazy-workspaces setup", function()
			assert.is_true(H.content_has(out .. "/init.lua", 'require%("lazy%-workspaces"%)%.setup'))
		end)

		it("new init.lua does not call lazy.setup directly", function()
			assert.is_true(H.content_lacks(out .. "/init.lua", 'require%("lazy"%)%.setup'))
		end)
	end)
end)

-- ── unit: migrate_flat_plugins ────────────────────────────────────────────────

describe("migrate_flat_plugins", function()
	local migrate = bootstrap._test.migrate_flat_plugins

	it("moves spec files into plugins/plugins/", function()
		local src = H.make_tree({ ["lua/plugins/foo.lua"] = 'return { "foo/bar" }' })
		local notify_stub = stub(vim, "notify")
		migrate(src .. "/lua")
		notify_stub:revert()
		assert.is_true(H.file_exists(src .. "/lua/plugins/plugins/foo.lua"))
		assert.is_false(H.file_exists(src .. "/lua/plugins/foo.lua"))
		H.cleanup(src)
	end)

	it("generates empty plugins/init.lua", function()
		local src = H.make_tree({ ["lua/plugins/foo.lua"] = 'return { "foo/bar" }' })
		local notify_stub = stub(vim, "notify")
		migrate(src .. "/lua")
		notify_stub:revert()
		assert.is_true(H.file_exists(src .. "/lua/plugins/init.lua"))
		assert.is_true(H.content_has(src .. "/lua/plugins/init.lua", "function M%.setup"))
		H.cleanup(src)
	end)

	it("skips init.lua generation when already exists, emits WARN", function()
		local src = H.make_tree({
			["lua/plugins/init.lua"] = "-- existing",
			["lua/plugins/foo.lua"]  = 'return { "foo/bar" }',
		})
		local warned = false
		local orig = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN and msg:match("already exists") then warned = true end
		end
		migrate(src .. "/lua")
		vim.notify = orig
		assert.is_true(warned)
		assert.is_true(H.content_has(src .. "/lua/plugins/init.lua", "-- existing"))
		H.cleanup(src)
	end)

	it("does not move existing init.lua into plugins/plugins/", function()
		local src = H.make_tree({
			["lua/plugins/init.lua"] = "-- existing",
			["lua/plugins/foo.lua"]  = 'return { "foo/bar" }',
		})
		local orig = vim.notify
		vim.notify = function() end
		migrate(src .. "/lua")
		vim.notify = orig
		assert.is_false(H.file_exists(src .. "/lua/plugins/plugins/init.lua"))
		H.cleanup(src)
	end)
end)

-- ── unit: write_config_init ───────────────────────────────────────────────────

describe("write_config_init", function()
	local write_ci = bootstrap._test.write_config_init

	it("generates init.lua requiring each .lua file", function()
		local src = H.make_tree({
			["lua/config/options.lua"] = "vim.opt.number = true",
			["lua/config/keymaps.lua"] = "-- keymaps",
		})
		write_ci(src .. "/lua/config")
		assert.is_true(H.content_has(src .. "/lua/config/init.lua", 'require%("config%.options"%)'))
		assert.is_true(H.content_has(src .. "/lua/config/init.lua", 'require%("config%.keymaps"%)'))
		H.cleanup(src)
	end)

	it("wraps requires in M.setup() with return M", function()
		local src = H.make_tree({ ["lua/config/opts.lua"] = "-- opts" })
		write_ci(src .. "/lua/config")
		assert.is_true(H.content_has(src .. "/lua/config/init.lua", "function M%.setup"))
		assert.is_true(H.content_has(src .. "/lua/config/init.lua", "^return M$"))
		H.cleanup(src)
	end)

	it("skips generation when init.lua already exists, emits WARN", function()
		local src = H.make_tree({
			["lua/config/init.lua"]    = "-- existing",
			["lua/config/options.lua"] = "-- opts",
		})
		local warned = false
		local orig = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN and msg:match("already exists") then warned = true end
		end
		write_ci(src .. "/lua/config")
		vim.notify = orig
		assert.is_true(warned)
		assert.is_true(H.content_has(src .. "/lua/config/init.lua", "-- existing"))
		H.cleanup(src)
	end)
end)

-- ── unit: detect_workspaces ──────────────────────────────────────────────────

describe("detect_workspaces", function()
	local detect = bootstrap._test.detect_workspaces

	it("detects flat workspace", function()
		local src = H.make_tree({ ["lua/myns/init.lua"] = "-- ns" })
		local ns = detect(src .. "/lua")
		assert.are.same({ "myns" }, ns)
		H.cleanup(src)
	end)

	it("detects slash-separated names under container dir", function()
		local src = H.make_tree({
			["lua/myconfig/common/init.lua"]   = "-- common",
			["lua/myconfig/personal/init.lua"] = "-- personal",
		})
		local ns = detect(src .. "/lua")
		table.sort(ns)
		assert.are.same({ "myconfig/common", "myconfig/personal" }, ns)
		H.cleanup(src)
	end)

	it("top-level init.lua wins — no descent into subdir", function()
		local src = H.make_tree({
			["lua/foo/init.lua"]     = "-- foo",
			["lua/foo/bar/init.lua"] = "-- bar is a submodule, not a workspace",
		})
		local ns = detect(src .. "/lua")
		assert.are.same({ "foo" }, ns)
		H.cleanup(src)
	end)

	it("emits WARN for loose .lua files in container", function()
		local src = H.make_tree({
			["lua/myconfig/common/init.lua"] = "-- common",
			["lua/myconfig/orphan.lua"]      = "-- orphan",
		})
		local warned = false
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN and msg:match("myconfig") and msg:match("loose") then
				warned = true
			end
		end
		detect(src .. "/lua")
		vim.notify = orig_notify
		assert.is_true(warned)
		H.cleanup(src)
	end)

	it("detects empty leaf dir (no lua files) alongside workspace with init.lua", function()
		local src = H.make_tree({
			["lua/myconfig/common/init.lua"]     = "-- common",
			["lua/myconfig/new/.gitkeep"]        = "",
		})
		local ns = detect(src .. "/lua")
		table.sort(ns)
		assert.are.same({ "myconfig/common", "myconfig/new" }, ns)
		H.cleanup(src)
	end)

	it("handles mixed flat and container dirs at same level", function()
		local src = H.make_tree({
			["lua/flat/init.lua"]            = "-- flat",
			["lua/container/child/init.lua"] = "-- child",
		})
		local ns = detect(src .. "/lua")
		table.sort(ns)
		assert.are.same({ "container/child", "flat" }, ns)
		H.cleanup(src)
	end)

	it("detects truly empty leaf dir as workspace (no lua files)", function()
		local src = H.make_tree({ ["lua/new/.gitkeep"] = "" })
		local ns = detect(src .. "/lua")
		assert.are.same({ "new" }, ns)
		H.cleanup(src)
	end)

	it("does not detect leaf dir with lua files as workspace (no init.lua)", function()
		local src = H.make_tree({ ["lua/plugins/foo.lua"] = "-- spec" })
		local ns = detect(src .. "/lua")
		assert.are.same({}, ns)
		H.cleanup(src)
	end)

	it("detects three-level deep workspace", function()
		local src = H.make_tree({
			["lua/org/team/config/init.lua"] = "-- config",
		})
		local ns = detect(src .. "/lua")
		assert.are.same({ "org/team/config" }, ns)
		H.cleanup(src)
	end)

	it("emits WARN with slash container name for deep nesting", function()
		local src = H.make_tree({
			["lua/org/team/config/init.lua"] = "-- config",
			["lua/org/team/orphan.lua"]      = "-- orphan",
		})
		local warned_name = nil
		local orig_notify = vim.notify
		vim.notify = function(msg, level)
			if level == vim.log.levels.WARN and msg:match("loose") then
				warned_name = msg:match("container '([^']+)'")
			end
		end
		detect(src .. "/lua")
		vim.notify = orig_notify
		assert.are.equal("org/team", warned_name)
		H.cleanup(src)
	end)
end)

-- ── unit: strip_lazy_init ─────────────────────────────────────────────────────

describe("strip_lazy_init", function()
	local strip = bootstrap._test.strip_lazy_init

	it("removes double-quote require", function()
		local lines = { 'require("myns.lazy_init")', "other_line" }
		local result = strip(lines, "myns")
		assert.are.same({ "other_line" }, result)
	end)

	it("removes single-quote require", function()
		local lines = { "require('myns.lazy_init')", "other_line" }
		local result = strip(lines, "myns")
		assert.are.same({ "other_line" }, result)
	end)

	it("preserves non-matching requires", function()
		local lines = { 'require("myns.set")', 'require("myns.remap")' }
		local result = strip(lines, "myns")
		assert.are.same(lines, result)
	end)

	it("removes multiple matching lines", function()
		local lines = { 'require("myns.lazy_init")', "x", 'require("myns.lazy_init")' }
		local result = strip(lines, "myns")
		assert.are.same({ "x" }, result)
	end)

	it("handles slash-separated workspace name (nested)", function()
		local lines = { 'require("myconfig.common.lazy_init")', "other" }
		local result = strip(lines, "myconfig/common")
		assert.are.same({ "other" }, result)
	end)
end)

-- ── unit: wrap_in_setup ───────────────────────────────────────────────────────

describe("wrap_in_setup", function()
	local wrap = bootstrap._test.wrap_in_setup

	it("adds M boilerplate", function()
		local result = wrap({ "vim.opt.number = true" })
		assert.are.equal("local M = {}", result[1])
		assert.are.equal("function M.setup()", result[3])
		assert.truthy(vim.tbl_contains(result, "end"))
		assert.truthy(vim.tbl_contains(result, "return M"))
	end)

	it("indents content lines with 2 spaces", function()
		local result = wrap({ "vim.opt.number = true" })
		assert.truthy(vim.tbl_contains(result, "  vim.opt.number = true"))
	end)

	it("strips trailing blank lines before wrapping", function()
		local result = wrap({ "vim.opt.number = true", "", "" })
		-- last line should be "return M", not blank
		assert.are.equal("return M", result[#result])
	end)

	it("preserves blank lines within content as empty strings", function()
		local result = wrap({ "line_a", "", "line_b" })
		assert.truthy(vim.tbl_contains(result, ""))
	end)
end)
