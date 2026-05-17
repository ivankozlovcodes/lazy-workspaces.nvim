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

	describe("plugin dir rename", function()
		it("renames lazy/ to plugins/", function()
			assert.is_true(H.dir_exists(out .. "/lua/johnnyjumper/plugins"))
		end)

		it("removes original lazy/ dir", function()
			assert.is_false(H.dir_exists(out .. "/lua/johnnyjumper/lazy"))
		end)

		it("preserves plugin spec files inside plugins/", function()
			assert.is_true(H.file_exists(out .. "/lua/johnnyjumper/plugins/init.lua"))
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

		it("includes johnnyjumper in enable list", function()
			assert.is_true(H.content_has(init_path, '"johnnyjumper"'))
		end)

		it("bootstraps lazy-workspaces", function()
			assert.is_true(H.content_has(init_path, "lazy%-workspaces"))
		end)

		it("calls lazy-workspaces collect", function()
			assert.is_true(H.content_has(init_path, "collect"))
		end)

		it("calls lazy.setup", function()
			assert.is_true(H.content_has(init_path, 'require%("lazy"%)%.setup'))
		end)

		it("sets workspace_root to output dir", function()
			assert.is_true(H.content_has(init_path, vim.pesc(out)))
		end)
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
