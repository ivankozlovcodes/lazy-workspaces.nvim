local M = {}

M.version = "0.1.5"

local _self_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")
local _opts = nil
local _scan_cache = nil -- populated by collect(); { cfg_name = { path, workspaces, specs } }
local _collect_warnings = {} -- { ws, spec_dir, loose_files[] } — reset each collect()
local opts_mod = require("lazy-workspaces.opts")

---@class WorkspaceSource
---@field source string     local path (absolute or ~) or git URL (git@, https://)
---@field branch string?    git branch (optional, defaults to repo default)

---@class LazyWorkspacesOpts
---@field configs table<string, string|WorkspaceSource>  config_name → source string or {source,branch} table
---@field specs string[]?  subdirectory names scanned for lazy specs (default: {"plugins"})
---@field auto_pull boolean?  pull git configs and local .git repos on startup (default: true)

---@class LazyWorkspacesSetupOpts : LazyWorkspacesOpts
---@field lazy LazyConfig?  opts forwarded verbatim to lazy.setup() (rocks, change_detection, etc.)

---@class ResolvedConfig
---@field name string        config name (key from opts.configs)
---@field path string        absolute local path to the config root
---@field workspaces string[] workspace rel-paths found under lua/

--- Recursively scan all subdirectories under lua_dir. No init.lua check — pure structure.
---@param lua_dir string
---@param prefix string?
---@return table[]  list of { name, rel, path, kids }
local function scan_dir(lua_dir, prefix)
	prefix = prefix or ""
	local entries = {}
	for _, dir in ipairs(vim.fn.glob(lua_dir .. "/*/", false, true)) do
		local name = dir:match("/([^/]+)/$")
		if not name then
			goto continue
		end
		local rel = prefix == "" and name or (prefix .. "/" .. name)
		local abs = dir:gsub("/$", "")
		entries[#entries + 1] = { name = name, rel = rel, path = abs, kids = scan_dir(abs, rel) }
		::continue::
	end
	return entries
end

--- Classify scanned entries into workspaces and spec dirs.
--- Spec dirs named in spec_dir_set are recognized at any nesting depth.
---@return table  { workspaces: string[], specs: table[] }
local function classify_dirs(entries, spec_dir_set)
	local workspaces = {}
	local specs = {}

	for _, e in ipairs(entries) do
		local has_init = vim.fn.filereadable(e.path .. "/init.lua") == 1

		if spec_dir_set[e.name] then
			specs[#specs + 1] = { name = e.name, path = e.path, via_init = has_init }
		elseif has_init then
			workspaces[#workspaces + 1] = e.rel
		elseif #e.kids > 0 then
			local child = classify_dirs(e.kids, spec_dir_set)
			if #child.workspaces > 0 then
				local loose = vim.fn.glob(e.path .. "/*.lua", false, true)
				if #loose > 0 then
					local names = {}
					for _, f in ipairs(loose) do
						names[#names + 1] = vim.fn.fnamemodify(f, ":t")
					end
					vim.notify(
						"[lazy-workspaces] container '"
							.. e.rel
							.. "' has loose files (not loaded as workspaces): "
							.. table.concat(names, ", "),
						vim.log.levels.WARN
					)
				end
				vim.list_extend(workspaces, child.workspaces)
				vim.list_extend(specs, child.specs)
			elseif #vim.fn.glob(e.path .. "/*.lua", false, true) == 0 then
				workspaces[#workspaces + 1] = e.rel
			end
		elseif #vim.fn.glob(e.path .. "/*.lua", false, true) == 0 then
			workspaces[#workspaces + 1] = e.rel
		end
	end

	return { workspaces = workspaces, specs = specs }
end

function M._get_scan_cache()
	return _scan_cache
end

function M._get_collect_warnings()
	return _collect_warnings
end

--- Compatibility: return workspace rel-paths under lua_dir (no spec dir exclusions).
--- Used by bootstrap.lua.
function M.detect_workspaces(lua_dir)
	return classify_dirs(scan_dir(lua_dir), {}).workspaces
end

--- Return list of config names in state that contain a given workspace name.
---@param state table
---@param ws_name string
---@return string[]
local function find_configs_with_ws(state, ws_name)
	local matches = {}
	for cfg, ws_map in pairs(state) do
		if type(ws_map) == "table" and ws_map[ws_name] ~= nil then
			matches[#matches + 1] = cfg
		end
	end
	return matches
end

---@param specs_opt string[]?
---@return table<string, true>
local function build_spec_dir_set(specs_opt)
	local set = {}
	for _, s in ipairs(specs_opt or { "plugins" }) do
		set[s] = true
	end
	return set
end

--- Scan one config root and classify its contents.
---@param path string  absolute path to config root
---@param spec_dir_set table
---@return table  { workspaces: string[], specs: table[] }
local function scan_config(path, spec_dir_set)
	return classify_dirs(scan_dir(path .. "/lua"), spec_dir_set)
end

--- Load a single spec file. Returns the table it returns, or nil on failure (emits WARN).
---@param file string
---@param label string  used in the WARN message
---@return table|nil
local function load_spec_file(file, label)
	local chunk, err = loadfile(file)
	if not chunk then
		vim.notify("[lazy-workspaces] failed to load " .. label .. ": " .. tostring(err), vim.log.levels.WARN)
		return nil
	end
	local ok, result = pcall(chunk)
	return (ok and type(result) == "table") and result or nil
end

--- Async pull all pullable configs: git URLs (clone or pull) and local paths that contain .git.
--- Calls on_done(failed_names) when all jobs finish. Calls on_done({}) immediately if nothing to pull.
---@param entries table[]  normalized entries from opts_mod.normalize()
---@param on_done fun(failed: string[])
local function pull_all_async(entries, on_done)
	local jobs = {}
	for _, e in ipairs(entries) do
		local path = opts_mod.local_path_for(e)
		local is_git_url = e.source:match("^https?://") or e.source:match("^git@")
		local cmd
		if is_git_url then
			if vim.fn.isdirectory(path) == 0 then
				cmd = { "git", "clone", "--filter=blob:none" }
				if e.branch then
					vim.list_extend(cmd, { "--branch", e.branch })
				end
				vim.list_extend(cmd, { e.source, path })
			else
				cmd = { "git", "-C", path, "pull", "--ff-only" }
				if e.branch then
					vim.list_extend(cmd, { "origin", e.branch })
				end
			end
		elseif vim.fn.isdirectory(path .. "/.git") == 1 then
			cmd = { "git", "-C", path, "pull", "--ff-only" }
			if e.branch then
				vim.list_extend(cmd, { "origin", e.branch })
			end
		end
		if cmd then
			jobs[#jobs + 1] = { name = e.name, cmd = cmd }
		end
	end

	if #jobs == 0 then
		on_done({})
		return
	end

	vim.notify("[lazy-workspaces] syncing " .. #jobs .. " config(s)...", vim.log.levels.INFO)

	local pending = #jobs
	local failed = {}
	for _, job in ipairs(jobs) do
		local name_ref = job.name
		vim.fn.jobstart(job.cmd, {
			on_exit = function(_, code)
				pending = pending - 1
				if code ~= 0 then
					failed[#failed + 1] = name_ref
				end
				if pending == 0 then
					on_done(failed)
				end
			end,
		})
	end
end

--- Resolve workspace sources, scan plugin specs, schedule workspace setup() calls.
--- Returns a flat list of lazy.nvim specs to pass to lazy.setup({ spec = ... }).
---@param opts LazyWorkspacesOpts
---@return table
function M.collect(opts)
	opts = opts_mod.apply_defaults(opts)
	local resolver = require("lazy-workspaces.resolver")
	local state_mod = require("lazy-workspaces.state")
	local specs = {}

	local entries = opts_mod.normalize(opts.configs or {})
	local spec_dir_set = build_spec_dir_set(opts.specs)

	---@type ResolvedConfig[]
	local resolved = {}
	local configs_map = {}
	local seen_paths = {}
	_scan_cache = {}
	_collect_warnings = {}

	for _, e in ipairs(entries) do
		local ok, path = pcall(resolver.resolve, e.source, e.branch)
		if not ok then
			vim.notify(
				"[lazy-workspaces] could not resolve config '"
					.. e.name
					.. "' ("
					.. tostring(e.source)
					.. "): "
					.. tostring(path),
				vim.log.levels.ERROR
			)
		else
			if not seen_paths[path] then
				seen_paths[path] = true
				if not vim.tbl_contains(vim.opt.rtp:get(), path) then
					vim.opt.rtp:prepend(path)
				end
			end

			local classified = scan_config(path, spec_dir_set)
			_scan_cache[e.name] = { path = path, workspaces = classified.workspaces, specs = classified.specs }

			for _, ns in ipairs(classified.specs) do
				if ns.via_init then
					local s = load_spec_file(ns.path .. "/init.lua", "spec " .. ns.path .. "/init.lua")
					if s then
						specs[#specs + 1] = s
					end
				else
					for _, file in ipairs(vim.fn.glob(ns.path .. "/*.lua", false, true)) do
						local s = load_spec_file(file, "neighbor spec " .. file)
						if s then
							specs[#specs + 1] = s
						end
					end
				end
			end

			if #classified.workspaces > 0 then
				resolved[#resolved + 1] = { name = e.name, path = path, workspaces = classified.workspaces }
				configs_map[e.name] = classified.workspaces
			end
		end
	end

	if opts.auto_pull then
		pull_all_async(entries, function(failed)
			for _, name in ipairs(failed) do
				vim.notify("[lazy-workspaces] auto-pull failed for '" .. name .. "'", vim.log.levels.WARN)
			end
		end)
	end

	-- Expose resolved config paths via vim.g.lw so workspace setup() calls can reference them.
	-- vim.g.lw.configs      → { config_name = local_path, ... }
	-- vim.g.lw.config_paths → { local_path, ... }  (flat list, usable as dirs = vim.g.lw.config_paths)
	local lw_configs = {}
	local lw_config_paths = {}
	for _, r in ipairs(resolved) do
		lw_configs[r.name] = r.path
		lw_config_paths[#lw_config_paths + 1] = r.path
	end
	vim.g.lw = { configs = lw_configs, config_paths = lw_config_paths }

	local effective = state_mod.reconcile(configs_map)

	for _, r in ipairs(resolved) do
		local cfg_effective = effective[r.name] or {}
		for _, ws_name in ipairs(r.workspaces) do
			if cfg_effective[ws_name] then
				local ws_root = r.path .. "/lua/" .. ws_name
				for _, spec_dir in ipairs(opts.specs or { "plugins" }) do
					local dir = ws_root .. "/" .. spec_dir
					if vim.fn.isdirectory(dir) == 1 then
						local lua_files = vim.fn.glob(dir .. "/*.lua", false, true)
						if #lua_files == 0 then
							_collect_warnings[#_collect_warnings + 1] = {
								ws = ws_name,
								spec_dir = spec_dir,
								dir = dir,
							}
						end
						for _, file in ipairs(lua_files) do
							local s = load_spec_file(file, "spec " .. file)
							if s then
								specs[#specs + 1] = s
							end
						end
					end
				end

				local ws_init = r.path .. "/lua/" .. ws_name .. "/init.lua"
				if vim.fn.filereadable(ws_init) == 1 then
					local chunk, load_err = loadfile(ws_init)
					if not chunk then
						vim.notify(
							"[lazy-workspaces] failed to load workspace '" .. ws_name .. "': " .. tostring(load_err),
							vim.log.levels.WARN
						)
					else
						local ok3, mod = pcall(chunk)
						if ok3 and type(mod) == "table" then
							if type(mod.setup) == "function" then
								vim.schedule(function()
									local ok4, err = pcall(mod.setup)
									if not ok4 then
										vim.notify(
											"[lazy-workspaces] workspace '" .. ws_name .. "' setup() error: " .. tostring(err),
											vim.log.levels.ERROR
										)
									end
								end)
							else
								specs[#specs + 1] = mod
							end
						end
					end
				end
			end
		end
	end

	if #_collect_warnings > 0 then
		vim.schedule(function()
			vim.notify(
				"[lazy-workspaces] empty spec dir(s) detected — run :checkhealth lazy-workspaces for details",
				vim.log.levels.WARN
			)
		end)
	end

	return specs
end

--- Apply include (true) or exclude (false) to a workspace in the JSON state.
---@param args table  nvim command args table
---@param target_val boolean
---@param verb string  "Include" or "Exclude"
local function apply_state(args, target_val, verb)
	local raw = vim.trim(args.args)
	if raw == "" then
		vim.notify("[lazy-workspaces] usage: LazyWorkspaces" .. verb .. " [config::]<workspace>", vim.log.levels.ERROR)
		return
	end

	local s = require("lazy-workspaces.state")
	local st = s.read()

	-- Explicit config::workspace format disambiguates when workspace name is shared across configs.
	local sep = raw:find("::", 1, true)
	if sep then
		local cfg_name = raw:sub(1, sep - 1)
		local ws_name = raw:sub(sep + 2)
		if not st[cfg_name] then
			vim.notify(
				"[lazy-workspaces] config '" .. cfg_name .. "' not found in lazy-workspaces.json",
				vim.log.levels.ERROR
			)
			return
		end
		if st[cfg_name][ws_name] == nil then
			vim.notify(
				"[lazy-workspaces] workspace '" .. ws_name .. "' not found in config '" .. cfg_name .. "'",
				vim.log.levels.ERROR
			)
			return
		end
		st[cfg_name][ws_name] = target_val
		s.write(st)
		vim.notify(
			"[lazy-workspaces] '"
				.. cfg_name
				.. "::"
				.. ws_name
				.. "' "
				.. (target_val and "included" or "excluded")
				.. " (restart Neovim to apply)",
			vim.log.levels.INFO
		)
		return
	end

	-- No :: — search all configs by workspace name.
	local matches = find_configs_with_ws(st, raw)
	if #matches == 0 then
		vim.notify(
			"[lazy-workspaces] workspace '" .. raw .. "' not found in lazy-workspaces.json",
			vim.log.levels.ERROR
		)
		return
	elseif #matches > 1 then
		table.sort(matches)
		local suggestions = {}
		for _, cfg in ipairs(matches) do
			suggestions[#suggestions + 1] = cfg .. "::" .. raw
		end
		vim.notify(
			"[lazy-workspaces] ambiguous workspace '" .. raw .. "' — use one of: " .. table.concat(suggestions, ", "),
			vim.log.levels.ERROR
		)
		return
	end

	st[matches[1]][raw] = target_val
	s.write(st)
	vim.notify(
		"[lazy-workspaces] '"
			.. raw
			.. "' "
			.. (target_val and "included" or "excluded")
			.. " (restart Neovim to apply)",
		vim.log.levels.INFO
	)
end

--- Build tab completion for Include/Exclude commands.
---@param want_val boolean  false = complete excluded (for Include), true = complete included (for Exclude)
---@return function
local function make_complete(want_val)
	return function(arglead)
		local st = require("lazy-workspaces.state").read()

		local out = {}
		local seen = {}
		for cfg, ws_map in pairs(st) do
			if type(ws_map) == "table" then
				for ws_name, included in pairs(ws_map) do
					if included == want_val then
						local completion = cfg .. "::" .. ws_name
						if not seen[completion] and completion:sub(1, #arglead) == arglead then
							seen[completion] = true
							out[#out + 1] = completion
						end
					end
				end
			end
		end
		return out
	end
end

--- Pull all configs then reconcile state with any newly discovered workspaces.
local function sync_configs()
	if not _opts or not _opts.configs then
		vim.notify("[lazy-workspaces] no configs configured", vim.log.levels.WARN)
		return
	end

	local resolved_opts = opts_mod.apply_defaults(_opts)
	local entries = opts_mod.normalize(resolved_opts.configs)
	local spec_dir_set = build_spec_dir_set(resolved_opts.specs)

	pull_all_async(entries, function(failed)
		local state_mod = require("lazy-workspaces.state")
		local configs_map = {}
		for _, e in ipairs(entries) do
			local path = opts_mod.local_path_for(e)
			if vim.fn.isdirectory(path) == 1 then
				local classified = scan_config(path, spec_dir_set)
				if #classified.workspaces > 0 then
					configs_map[e.name] = classified.workspaces
				end
			end
		end

		local before = state_mod.read()
		state_mod.reconcile(configs_map)
		local after = state_mod.read()

		local new_ws = {}
		for cfg, ws_map in pairs(after) do
			for ws in pairs(ws_map) do
				if not before[cfg] or before[cfg][ws] == nil then
					new_ws[#new_ws + 1] = cfg .. "::" .. ws
				end
			end
		end

		if #failed > 0 then
			vim.notify("[lazy-workspaces] pull failed: " .. table.concat(failed, ", "), vim.log.levels.ERROR)
		end
		if #new_ws > 0 then
			vim.notify(
				"[lazy-workspaces] new workspaces: " .. table.concat(new_ws, ", ") .. " — restart Neovim to apply",
				vim.log.levels.INFO
			)
		else
			local suffix = #failed > 0 and " (with errors)" or ""
			vim.notify("[lazy-workspaces] synced" .. suffix .. " — no new workspaces", vim.log.levels.INFO)
		end
	end)
end

local function register_commands()
	vim.api.nvim_create_user_command("LazyWorkspacesBootstrap", function(args)
		require("lazy-workspaces.bootstrap").command(args)
	end, { nargs = "*", desc = "Bootstrap nvim config to lazy-workspaces format", complete = "dir" })

	vim.api.nvim_create_user_command("LazyWorkspacesInclude", function(args)
		apply_state(args, true, "Include")
	end, {
		nargs = 1,
		desc = "Include a workspace (restart Neovim to apply)",
		complete = make_complete(false),
	})

	vim.api.nvim_create_user_command("LazyWorkspacesExclude", function(args)
		apply_state(args, false, "Exclude")
	end, {
		nargs = 1,
		desc = "Exclude a workspace (restart Neovim to apply)",
		complete = make_complete(true),
	})

	vim.api.nvim_create_user_command(
		"LazyWorkspacesSync",
		sync_configs,
		{ nargs = 0, desc = "Pull git configs and reconcile workspace state" }
	)
end

--- Entry point. When called by user (before lazy.setup), bootstraps lazy.nvim, collects
--- workspace specs, and calls lazy.setup(). When called by lazy as a config hook (second
--- invocation), only registers user commands.
---@param user_opts LazyWorkspacesSetupOpts?
function M.setup(user_opts)
	local ok, lazy_cfg = pcall(require, "lazy.core.config")
	if ok and lazy_cfg.options ~= nil then
		-- called by lazy config hook (old API compat)
		register_commands()
		return
	end
	user_opts = user_opts or {}
	_opts = user_opts

	-- Bootstrap lazy.nvim only if not already on rtp
	if not pcall(require, "lazy") then
		local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
		if not (vim.uv or vim.loop).fs_stat(lazypath) then
			vim.fn.system({
				"git",
				"clone",
				"--filter=blob:none",
				"https://github.com/folke/lazy.nvim.git",
				"--branch=stable",
				lazypath,
			})
		end
		vim.opt.rtp:prepend(lazypath)
	end

	local workspace_specs = M.collect({ configs = user_opts.configs, specs = user_opts.specs })

	register_commands()

	local lw_dev = vim.env.LW_DEV ~= nil
	local self_spec = {
		"ivankozlovcodes/lazy-workspaces.nvim",
		lazy = false,
		priority = 1000,
		dev = lw_dev,
	}

	local lazy_opts = user_opts.lazy or {}
	local full_spec = { self_spec }
	if lazy_opts.spec ~= nil then
		table.insert(full_spec, lazy_opts.spec)
		lazy_opts.spec = nil
	end
	table.insert(full_spec, workspace_specs)

	require("lazy").setup(vim.tbl_deep_extend("force", lazy_opts, { spec = full_spec }))
end

M._test = {
	self_path = function()
		return _self_path
	end,
}

function M._get_opts()
	return _opts
end

return M
