local H = require("tests.helpers")
local state = require("lazy-workspaces.state")
local lw = require("lazy-workspaces")

local fx = {
	simple       = require("tests.fixtures.workspaces.simple"),
	with_plugins = require("tests.fixtures.workspaces.with_plugins"),
	multi        = require("tests.fixtures.workspaces.multi"),
	nested       = require("tests.fixtures.workspaces.nested"),
	custom_spec  = require("tests.fixtures.workspaces.custom_spec"),
	neighbor_spec_no_init   = require("tests.fixtures.workspaces.neighbor_spec_no_init"),
	neighbor_workspace      = require("tests.fixtures.workspaces.neighbor_workspace"),
	neighbor_spec_with_init = require("tests.fixtures.workspaces.neighbor_spec_with_init"),
	nested_neighbor_spec_no_init   = require("tests.fixtures.workspaces.nested_neighbor_spec_no_init"),
	nested_neighbor_spec_with_init = require("tests.fixtures.workspaces.nested_neighbor_spec_with_init"),
}

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
	-- ── error handling ──────────────────────────────────────────────────────

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
				if level == vim.log.levels.ERROR then errored = true end
			end
			local specs = lw.collect({ configs = { bad = { source = "/nonexistent/path/xyz" } } })
			vim.notify = orig
			assert.is_true(errored)
			assert.are.same({}, specs)
		end)
	end)

	-- ── simple: single workspace, no plugins dir ────────────────────────────

	it("returns empty specs when workspace has no plugins/ dir", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.same({}, specs)
		end)
	end)

	it("sets vim.g.lw.config_paths with resolved config paths", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			local lw_g = vim.g.lw
			H.cleanup(root)
			assert.is_not_nil(lw_g)
			assert.is_true(vim.tbl_contains(lw_g.config_paths, root))
		end)
	end)

	it("sets vim.g.lw.configs with name → path mapping", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			local lw_g = vim.g.lw
			H.cleanup(root)
			assert.are.equal(root, lw_g.configs.cfg1)
		end)
	end)

	it("adds workspace path to rtp", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			local rtp = vim.opt.rtp:get()
			local found = vim.tbl_contains(rtp, root)
			H.cleanup(root)
			assert.is_true(found)
		end)
	end)

	it("does not add workspace path to rtp twice on repeated calls", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			lw.collect({ configs = { cfg1 = { source = root } } })
			local count = 0
			for _, p in ipairs(vim.opt.rtp:get()) do
				if p == root then count = count + 1 end
			end
			H.cleanup(root)
			assert.are.equal(1, count)
		end)
	end)

	-- ── with_plugins: single workspace + plugins/ dir ──────────────────────

	it("returns specs from workspace plugins/ dir", function()
		with_state(function()
			local root = H.make_tree(fx.with_plugins.tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(fx.with_plugins.SPEC_COUNT, #specs)
		end)
	end)

	it("collects multiple spec files from plugins/", function()
		with_state(function()
			local root = H.make_tree(fx.with_plugins.tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.is_true(#specs > 1)
		end)
	end)

	it("excludes workspace excluded in state", function()
		with_state(function()
			local root = H.make_tree(fx.with_plugins.tree)
			state.write({ cfg1 = { [fx.with_plugins.WS] = false } })
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.same({}, specs)
		end)
	end)

	it("includes workspace included in state", function()
		with_state(function()
			local root = H.make_tree(fx.with_plugins.tree)
			state.write({ cfg1 = { [fx.with_plugins.WS] = true } })
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(fx.with_plugins.SPEC_COUNT, #specs)
		end)
	end)

	it("skips malformed spec files with WARN", function()
		with_state(function()
			local tree = vim.tbl_extend("force", fx.with_plugins.tree, {
				["lua/" .. fx.with_plugins.WS .. "/plugins/bad.lua"] = "this is not valid lua %%%",
			})
			local root = H.make_tree(tree)
			local warned = false
			local orig = vim.notify
			vim.notify = function(_, level)
				if level == vim.log.levels.WARN then warned = true end
			end
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			vim.notify = orig
			H.cleanup(root)
			assert.is_true(warned)
			assert.are.equal(fx.with_plugins.SPEC_COUNT, #specs)
		end)
	end)

	it("includes non-lazy-spec tables (cannot distinguish from valid specs)", function()
		with_state(function()
			local tree = vim.tbl_extend("force", fx.simple.tree, {
				["lua/" .. fx.simple.WS .. "/plugins/config_table.lua"] = "return { key = 'value' }",
			})
			local root = H.make_tree(tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	-- ── empty spec dir warnings ───────────────────────────────────────────────

	it("records warning when spec dir exists but has no .lua files", function()
		with_state(function()
			local tree = vim.tbl_extend("force", fx.simple.tree, {
				["lua/" .. fx.simple.WS .. "/plugins/.keep"] = "",
			})
			local root = H.make_tree(tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			local warnings = lw._get_collect_warnings()
			assert.are.equal(1, #warnings)
			assert.are.equal(fx.simple.WS, warnings[1].ws)
			assert.are.equal("plugins", warnings[1].spec_dir)
		end)
	end)

	it("no warning when spec dir has .lua files", function()
		with_state(function()
			local root = H.make_tree(fx.with_plugins.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(0, #lw._get_collect_warnings())
		end)
	end)

	it("no warning when spec dir does not exist", function()
		with_state(function()
			local root = H.make_tree(fx.simple.tree)
			lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(0, #lw._get_collect_warnings())
		end)
	end)

	it("skips non-table return values from spec files silently", function()
		with_state(function()
			local tree = vim.tbl_extend("force", fx.simple.tree, {
				["lua/" .. fx.simple.WS .. "/plugins/not_a_spec.lua"] = "return 'just a string'",
				["lua/" .. fx.simple.WS .. "/plugins/valid.lua"]      = "return { 'foo/bar' }",
			})
			local root = H.make_tree(tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	-- ── config load order ─────────────────────────────────────────────────

	it("init.lua returning plain spec table is collected into specs", function()
		with_state(function()
			local tree = {
				["lua/ws/init.lua"]        = "return { 'foo/bar' }",
				["lua/ws/plugins/baz.lua"] = "return { 'baz/qux' }",
			}
			local root = H.make_tree(tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(2, #specs)
		end)
	end)

	it("init.lua returning plain spec table without plugins/ dir yields one spec", function()
		with_state(function()
			local root = H.make_tree({ ["lua/ws/init.lua"] = "return { 'foo/bar' }" })
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(1, #specs)
		end)
	end)

	it("array-style configs run workspace setup() in declared order", function()
		with_state(function()
			local mk_init = function(val)
				return "local M = {}\nfunction M.setup() vim.g.lw_order_test = '" .. val .. "' end\nreturn M"
			end
			local root1 = H.make_tree({ ["lua/ws/init.lua"] = mk_init("first") })
			local root2 = H.make_tree({ ["lua/ws/init.lua"] = mk_init("second") })
			vim.g.lw_order_test = nil
			lw.collect({ configs = { { source = root1 }, { source = root2 } } })
			vim.wait(100)
			H.cleanup(root1)
			H.cleanup(root2)
			assert.are.equal("second", vim.g.lw_order_test)
		end)
	end)

	it("reversing array-style config order reverses setup() execution", function()
		with_state(function()
			local mk_init = function(val)
				return "local M = {}\nfunction M.setup() vim.g.lw_order_test = '" .. val .. "' end\nreturn M"
			end
			local root1 = H.make_tree({ ["lua/ws/init.lua"] = mk_init("first") })
			local root2 = H.make_tree({ ["lua/ws/init.lua"] = mk_init("second") })
			vim.g.lw_order_test = nil
			lw.collect({ configs = { { source = root2 }, { source = root1 } } })
			vim.wait(100)
			H.cleanup(root1)
			H.cleanup(root2)
			assert.are.equal("first", vim.g.lw_order_test)
		end)
	end)

	-- ── multi: multiple sibling workspaces in same config root ──────────────

	it("collects specs from multiple workspaces in same config", function()
		with_state(function()
			local root = H.make_tree(fx.multi.tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(fx.multi.SPEC_COUNT, #specs)
		end)
	end)

	-- ── nested: container dir pattern (lua/group/common/, lua/group/personal/) ─

	it("detects and loads workspaces under container dir", function()
		with_state(function()
			local root = H.make_tree(fx.nested.tree)
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(fx.nested.SPEC_COUNT, #specs)
		end)
	end)

	it("excludes nested workspace by full slash-separated path key", function()
		with_state(function()
			local root = H.make_tree(fx.nested.tree)
			state.write({ cfg1 = { [fx.nested.WS_COMMON] = false } })
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.equal(fx.nested.SPEC_COUNT - 1, #specs)
		end)
	end)

	it("excludes all nested workspaces when all marked false", function()
		with_state(function()
			local root = H.make_tree(fx.nested.tree)
			state.write({ cfg1 = {
				[fx.nested.WS_COMMON]   = false,
				[fx.nested.WS_PERSONAL] = false,
			} })
			local specs = lw.collect({ configs = { cfg1 = { source = root } } })
			H.cleanup(root)
			assert.are.same({}, specs)
		end)
	end)

	-- ── custom_spec: non-standard spec directory ────────────────────────────

	it("loads specs from custom spec dir when specified in opts.specs", function()
		with_state(function()
			local f = fx.custom_spec
			local root = H.make_tree(f.tree)
			local specs = lw.collect(H.collect_args(root, f.opts))
			H.cleanup(root)
			assert.are.equal(f.SPEC_COUNT, #specs)
		end)
	end)
end)

-- ── neighbor spec dirs at config root ────────────────────────────────────────
-- Spec dirs can sit beside workspaces at the lua/ root (not just inside them).

describe("neighbor spec dirs at config root", function()
	-- neighbor_spec_no_init: spec-named dir without init.lua → load individual files.
	-- NEW — not yet implemented.
	describe("spec-named neighbor dir without init.lua loads individual files", function()
		local f = fx.neighbor_spec_no_init

		it("loads individual .lua files from neighbor spec dir as specs", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				local specs = lw.collect(H.collect_args(root, f.opts))
				H.cleanup(root)
				assert.are.equal(f.SPEC_COUNT, #specs)
			end)
		end)

		it("neighbor spec dir is not registered as workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS])
				assert.is_nil(st.cfg1 and st.cfg1[f.SPEC_DIR])
			end)
		end)

		it("dirs not named in specs are not loaded", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				local specs = lw.collect(H.collect_args(root, f.opts))
				H.cleanup(root)
				assert.are.equal(f.SPEC_COUNT, #specs)
			end)
		end)
	end)

	-- neighbor_workspace: neighbor dir with init.lua NOT in specs → workspace.
	-- Existing behavior; tests are regression guards.
	describe("neighbor dir with init.lua not in specs is a workspace", function()
		local f = fx.neighbor_workspace

		it("detects both default and plugins as workspaces", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS_DEFAULT])
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS_PLUGINS])
			end)
		end)

		it("dir without init.lua and not named in specs is not a workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_nil(st.cfg1 and st.cfg1["util"])
			end)
		end)
	end)

	-- neighbor_spec_with_init: neighbor dir with init.lua AND named in specs → spec dir.
	-- NEW — not yet implemented.
	describe("neighbor dir with init.lua named in specs is a spec dir not workspace", function()
		local f = fx.neighbor_spec_with_init

		it("loads spec from neighbor spec dir via init.lua", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				local specs = lw.collect(H.collect_args(root, f.opts))
				H.cleanup(root)
				assert.are.equal(f.SPEC_COUNT, #specs)
			end)
		end)

		it("does not register neighbor spec dir as a workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_nil(st.cfg1 and st.cfg1[f.SPEC_DIR])
			end)
		end)

		it("still detects default as workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS])
			end)
		end)
	end)
end)

-- ── neighbor spec dirs inside container dirs ─────────────────────────────────
-- Spec dirs work at any nesting depth, not just at lua/ root.

describe("neighbor spec dirs inside container dirs", function()
	describe("spec-named dir without init.lua inside container loads individual files", function()
		local f = fx.nested_neighbor_spec_no_init

		it("loads individual .lua files from nested neighbor spec dir", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				local specs = lw.collect(H.collect_args(root, f.opts))
				H.cleanup(root)
				assert.are.equal(f.SPEC_COUNT, #specs)
			end)
		end)

		it("nested neighbor spec dir is not registered as workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS])
				assert.is_nil(st.cfg1 and st.cfg1[f.SPEC_DIR])
			end)
		end)

		it("detects container workspace by slash-separated path", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS])
			end)
		end)
	end)

	describe("spec-named dir with init.lua inside container is loaded via init.lua", function()
		local f = fx.nested_neighbor_spec_with_init

		it("loads spec via init.lua from nested neighbor spec dir", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				local specs = lw.collect(H.collect_args(root, f.opts))
				H.cleanup(root)
				assert.are.equal(f.SPEC_COUNT, #specs)
			end)
		end)

		it("does not register nested neighbor spec dir as workspace", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_nil(st.cfg1 and st.cfg1[f.SPEC_DIR])
			end)
		end)

		it("detects container workspace by slash-separated path", function()
			with_state(function()
				local root = H.make_tree(f.tree)
				lw.collect(H.collect_args(root, f.opts))
				local st = state.read()
				H.cleanup(root)
				assert.is_not_nil(st.cfg1 and st.cfg1[f.WS])
			end)
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
