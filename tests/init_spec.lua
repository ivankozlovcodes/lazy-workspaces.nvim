local H = require("tests.helpers")
local state = require("lazy-workspaces.state")
local lw = require("lazy-workspaces")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function make_workspace(extra_files)
	local files = {
		["lua/mws/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
	}
	if extra_files then
		for k, v in pairs(extra_files) do
			files[k] = v
		end
	end
	return H.make_tree(files)
end

local function with_state(fn)
	local tmp = vim.fn.tempname() .. ".json"
	state._set_path(tmp)
	local ok, err = pcall(fn)
	state._reset_path()
	if vim.fn.filereadable(tmp) == 1 then
		vim.fn.delete(tmp)
	end
	if not ok then
		error(err, 2)
	end
end

-- ── M._test.self_path() ───────────────────────────────────────────────────────

describe("_test.self_path()", function()
	it("returns a valid directory", function()
		assert.is_true(H.dir_exists(lw._test.self_path()))
	end)

	it("contains lua/ subdirectory", function()
		assert.is_true(H.dir_exists(lw._test.self_path() .. "/lua"))
	end)

	it("contains lua/lazy-workspaces/ subdirectory", function()
		assert.is_true(H.dir_exists(lw._test.self_path() .. "/lua/lazy-workspaces"))
	end)
end)

-- ── M.collect() ──────────────────────────────────────────────────────────────

describe("collect()", function()
	it("returns empty list when workspaces is nil", function()
		with_state(function()
			local specs = lw.collect({})
			assert.are.same({}, specs)
		end)
	end)

	it("returns empty list when workspaces table is empty", function()
		with_state(function()
			local specs = lw.collect({ configs = {} })
			assert.are.same({}, specs)
		end)
	end)

	it("emits ERROR and returns empty list on bad file:// path", function()
		with_state(function()
			local errored = false
			local orig = vim.notify
			vim.notify = function(_, level)
				if level == vim.log.levels.ERROR then
					errored = true
				end
			end
			local specs = lw.collect({ configs = { bad = { source = "/nonexistent/path/xyz" } } })
			vim.notify = orig
			assert.is_true(errored)
			assert.are.same({}, specs)
		end)
	end)

	it("returns empty specs when workspace has no plugins/ dir", function()
		with_state(function()
			local root = make_workspace()
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.same({}, specs)
		end)
	end)

	it("returns specs from workspace plugins/ dir", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/foo.lua"] = "return { 'foo/bar', opts = {} }",
			})
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	it("collects multiple spec files from plugins/", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/foo.lua"] = "return { 'foo/bar' }",
				["lua/mws/plugins/baz.lua"] = "return { 'baz/qux' }",
			})
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(2, #specs)
		end)
	end)

	it("skips malformed spec files with WARN", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/bad.lua"] = "this is not valid lua %%%",
				["lua/mws/plugins/good.lua"] = "return { 'ok/plugin' }",
			})
			local warned = false
			local orig = vim.notify
			vim.notify = function(_, level)
				if level == vim.log.levels.WARN then
					warned = true
				end
			end
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			vim.notify = orig
			H.cleanup(root)
			assert.is_true(warned)
			assert.are.equal(1, #specs)
		end)
	end)

	it("excludes workspace excluded in state", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/foo.lua"] = "return { 'foo/bar' }",
			})
			-- pre-write state with mws excluded
			state.write({ ws1 = { mws = false } })
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.same({}, specs)
		end)
	end)

	it("includes workspace included in state", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/foo.lua"] = "return { 'foo/bar' }",
			})
			state.write({ ws1 = { mws = true } })
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	it("adds workspace path to rtp", function()
		with_state(function()
			local root = make_workspace()
			lw.collect({ configs = { ws1 = { source = root } } })
			local rtp = vim.opt.rtp:get()
			local found = vim.tbl_contains(rtp, root)
			H.cleanup(root)
			assert.is_true(found)
		end)
	end)

	it("does not add workspace path to rtp twice on repeated calls", function()
		with_state(function()
			local root = make_workspace()
			lw.collect({ configs = { ws1 = { source = root } } })
			lw.collect({ configs = { ws1 = { source = root } } })
			local count = 0
			for _, p in ipairs(vim.opt.rtp:get()) do
				if p == root then count = count + 1 end
			end
			H.cleanup(root)
			assert.are.equal(1, count)
		end)
	end)

	it("loads specs from custom spec dir (lazy/) when specified in opts.specs", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/lazy/foo.lua"] = "return { 'foo/bar' }",
			})
			local specs = lw.collect({ configs = { ws1 = { source = root } }, specs = { "lazy" } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	it("includes non-lazy-spec tables (cannot distinguish from valid specs)", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/config_table.lua"] = "return { key = 'value' }",
			})
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			-- table passes through — lazy.setup() would receive it and may error
			assert.are.equal(1, #specs)
		end)
	end)

	it("skips non-table return values from spec files silently", function()
		with_state(function()
			local root = make_workspace({
				["lua/mws/plugins/not_a_spec.lua"] = "return 'just a string'",
				["lua/mws/plugins/valid.lua"]       = "return { 'foo/bar' }",
			})
			local specs = lw.collect({ configs = { ws1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	it("collects specs from multiple workspaces in same config", function()
		with_state(function()
			local root = H.make_tree({
				["lua/ws_a/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
				["lua/ws_a/plugins/alpha.lua"] = "return { 'a/alpha' }",
				["lua/ws_b/init.lua"] = "local M = {}\nfunction M.setup() end\nreturn M",
				["lua/ws_b/plugins/beta.lua"] = "return { 'b/beta' }",
			})
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(2, #specs)
		end)
	end)
end)

-- ── M.setup() called_by_lazy guard ───────────────────────────────────────────
-- Simulate lazy calling setup() as a config hook by injecting a fake
-- lazy.core.config into package.preload with options set.

describe("setup() called_by_lazy guard", function()
	local function fake_lazy_config(has_options)
		package.preload["lazy.core.config"] = function()
			return { options = has_options and {} or nil }
		end
	end

	after_each(function()
		package.preload["lazy.core.config"] = nil
		package.loaded["lazy.core.config"] = nil
		pcall(vim.api.nvim_del_user_command, "LazyWorkspacesBootstrap")
		pcall(vim.api.nvim_del_user_command, "LazyWorkspacesInclude")
		pcall(vim.api.nvim_del_user_command, "LazyWorkspacesExclude")
	end)

	it("registers commands when lazy.core.config.options is set", function()
		fake_lazy_config(true)
		lw.setup({})
		local cmds = vim.api.nvim_get_commands({})
		assert.is_not_nil(cmds["LazyWorkspacesBootstrap"])
		assert.is_not_nil(cmds["LazyWorkspacesInclude"])
		assert.is_not_nil(cmds["LazyWorkspacesExclude"])
	end)

	it("does not error when called by lazy", function()
		fake_lazy_config(true)
		assert.has_no_error(function() lw.setup({}) end)
	end)

	it("calling setup twice when called_by_lazy does not error", function()
		fake_lazy_config(true)
		assert.has_no_error(function()
			lw.setup({})
			lw.setup({})
		end)
	end)
end)

-- ── generated init.lua shape (via write_root_init) ───────────────────────────

describe("write_root_init output shape", function()
	local bootstrap = require("lazy-workspaces.bootstrap")
	local write_ri = bootstrap._test.write_root_init

	it("calls lazy-workspaces setup not lazy.setup", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_has(out .. "/init.lua", 'require%("lazy%-workspaces"%)%.setup'))
		assert.is_true(H.content_lacks(out .. "/init.lua", 'require%("lazy"%)%.setup'))
		H.cleanup(out)
	end)

	it("does not call collect directly", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_lacks(out .. "/init.lua", "%.collect%("))
		H.cleanup(out)
	end)

	it("contains lazy-workspaces bootstrap", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_has(out .. "/init.lua", "lazy%-workspaces%.nvim"))
		H.cleanup(out)
	end)

	it("does not bootstrap lazy.nvim directly", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_lacks(out .. "/init.lua", "lazy%.nvim"))
		H.cleanup(out)
	end)

	it("includes workspace url with out_dir path", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_has(out .. "/init.lua", vim.pesc(out)))
		H.cleanup(out)
	end)

	it("includes configs opt key", function()
		local out = vim.fn.tempname()
		vim.fn.mkdir(out, "p")
		write_ri(out)
		assert.is_true(H.content_has(out .. "/init.lua", "configs"))
		H.cleanup(out)
	end)
end)
