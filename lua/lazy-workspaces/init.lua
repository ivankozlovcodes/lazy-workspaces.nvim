local M = {}

local _self_path = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

---@class WorkspaceSource
---@field url string        file:// path or git URL
---@field branch string?    git branch (optional, defaults to repo default)

---@class LazyWorkspacesOpts
---@field configs table<string, string|WorkspaceSource>  config_name → url string or {url,branch} table

---@class LazyWorkspacesSetupOpts : LazyWorkspacesOpts
---@field lazy table?  opts forwarded verbatim to lazy.setup() (rocks, change_detection, etc.)

--- Recursively find workspace folders (dirs containing init.lua) under lua_dir.
--- Returns slash-separated relative names: "ws" or "myconfig/common".
---@param lua_dir string
---@param prefix string?
---@return string[]
local function detect_workspaces(lua_dir, prefix)
	prefix = prefix or ""
	local result = {}
	for _, dir in ipairs(vim.fn.glob(lua_dir .. "/*/", false, true)) do
		local name = dir:match("/([^/]+)/$")
		if not name then
			goto continue
		end
		local rel = prefix == "" and name or (prefix .. "/" .. name)
		local d = dir:gsub("/$", "")
		if vim.fn.filereadable(d .. "/init.lua") == 1 then
			result[#result + 1] = rel
		else
			local children = detect_workspaces(d, rel)
			if #children > 0 then
				local loose = vim.fn.glob(d .. "/*.lua", false, true)
				if #loose > 0 then
					local names = {}
					for _, f in ipairs(loose) do
						names[#names + 1] = vim.fn.fnamemodify(f, ":t")
					end
					vim.notify(
						"[lazy-workspaces] container '"
							.. rel
							.. "' has loose files (not loaded as workspaces): "
							.. table.concat(names, ", "),
						vim.log.levels.WARN
					)
				end
				vim.list_extend(result, children)
			end
		end
		::continue::
	end
	return result
end

M.detect_workspaces = detect_workspaces

--- Extract url and branch from a workspaces map value.
---@param value string|WorkspaceSource
---@return string, string|nil
local function parse_source(value)
	if type(value) == "string" then
		return value, nil
	elseif type(value) == "table" then
		return value.url, value.branch
	end
	error("invalid workspace source type: " .. type(value))
end

--- Parse command argument into optional config name and workspace name.
--- "config/ws" → "config", "ws"
--- "ws"        → nil, "ws"
---@param arg string
---@return string|nil, string
local function parse_cmd_arg(arg)
	local slash = arg:find("/", 1, true)
	if slash then
		return arg:sub(1, slash - 1), arg:sub(slash + 1)
	end
	return nil, arg
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

--- Resolve workspace sources, scan plugin specs, schedule workspace setup() calls.
--- Returns a flat list of lazy.nvim specs to pass to lazy.setup({ spec = ... }).
---@param opts LazyWorkspacesOpts
---@return table
function M.collect(opts)
	opts = opts or {}
	local resolver = require("lazy-workspaces.resolver")
	local state_mod = require("lazy-workspaces.state")
	local specs = {}

	-- Pass 1: resolve each config URL → local path, scan workspace dirs on disk
	local resolved = {} -- { cfg_name, path, ws_names[] }
	local configs_map = {} -- { cfg_name = [ws_names] } for reconcile
	local seen_paths = {}

	for cfg_name, value in pairs(opts.configs or {}) do
		local url, branch = parse_source(value)
		local ok, path = pcall(resolver.resolve, url, branch)
		if not ok then
			vim.notify(
				"[lazy-workspaces] could not resolve config '"
					.. cfg_name
					.. "' ("
					.. tostring(url)
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

			local ws_names = detect_workspaces(path .. "/lua")
			if #ws_names > 0 then
				resolved[#resolved + 1] = { cfg_name = cfg_name, path = path, ws_names = ws_names }
				configs_map[cfg_name] = ws_names
			end
		end
	end

	-- Reconcile JSON state: auto-include new workspaces, respect excluded, warn stale
	local effective = state_mod.reconcile(configs_map)

	-- Pass 2: load plugin specs and schedule setup() for included workspaces only
	for _, entry in ipairs(resolved) do
		local cfg_effective = effective[entry.cfg_name] or {}
		for _, ws_name in ipairs(entry.ws_names) do
			if cfg_effective[ws_name] then
				local plugins_dir = entry.path .. "/lua/" .. ws_name .. "/plugins"
				if vim.fn.isdirectory(plugins_dir) == 1 then
					for _, file in ipairs(vim.fn.glob(plugins_dir .. "/*.lua", false, true)) do
						local chunk, err = loadfile(file)
						if not chunk then
							vim.notify(
								"[lazy-workspaces] failed to load spec " .. file .. ": " .. tostring(err),
								vim.log.levels.WARN
							)
						else
							local ok2, spec = pcall(chunk)
							if ok2 and type(spec) == "table" then
								specs[#specs + 1] = spec
							end
						end
					end
				end

				local ws_init = entry.path .. "/lua/" .. ws_name .. "/init.lua"
				vim.schedule(function()
					local chunk, load_err = loadfile(ws_init)
					if not chunk then
						vim.notify(
							"[lazy-workspaces] failed to load workspace '" .. ws_name .. "': " .. tostring(load_err),
							vim.log.levels.WARN
						)
						return
					end
					local ok3, mod = pcall(chunk)
					if ok3 and type(mod) == "table" and type(mod.setup) == "function" then
						local ok4, err = pcall(mod.setup)
						if not ok4 then
							vim.notify(
								"[lazy-workspaces] workspace '" .. ws_name .. "' setup() error: " .. tostring(err),
								vim.log.levels.ERROR
							)
						end
					end
				end)
			end
		end
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
		vim.notify("[lazy-workspaces] usage: LazyWorkspaces" .. verb .. " [config/]<workspace>", vim.log.levels.ERROR)
		return
	end

	local s = require("lazy-workspaces.state")
	local st = s.read()
	local cfg_name, ws_name = parse_cmd_arg(raw)

	if cfg_name then
		if not st[cfg_name] then
			vim.notify(
				"[lazy-workspaces] config '" .. cfg_name .. "' not found in lazy-workspaces.json (will be added)",
				vim.log.levels.WARN
			)
			st[cfg_name] = {}
		elseif st[cfg_name][ws_name] == nil then
			vim.notify(
				"[lazy-workspaces] '"
					.. cfg_name
					.. "/"
					.. ws_name
					.. "' not found in lazy-workspaces.json (will be added)",
				vim.log.levels.WARN
			)
		end
		st[cfg_name][ws_name] = target_val
	else
		local matches = find_configs_with_ws(st, ws_name)
		if #matches == 0 then
			vim.notify(
				"[lazy-workspaces] workspace '" .. ws_name .. "' not found in lazy-workspaces.json",
				vim.log.levels.ERROR
			)
			return
		elseif #matches > 1 then
			table.sort(matches)
			local suggestions = {}
			for _, cfg in ipairs(matches) do
				suggestions[#suggestions + 1] = cfg .. "/" .. ws_name
			end
			vim.notify(
				"[lazy-workspaces] ambiguous workspace '"
					.. ws_name
					.. "' — use one of: "
					.. table.concat(suggestions, ", "),
				vim.log.levels.ERROR
			)
			return
		else
			st[matches[1]][ws_name] = target_val
		end
	end

	s.write(st)
	vim.notify(
		"[lazy-workspaces] '"
			.. (cfg_name and (cfg_name .. "/") or "")
			.. ws_name
			.. "' "
			.. (target_val and "included" or "excluded")
			.. " (restart Neovim to apply)",
		vim.log.levels.INFO
	)
end

--- Build tab completion for Include/Exclude commands.
--- want_val: the current state to complete (false for Include = show excluded, true for Exclude = show included)
---@param want_val boolean
---@return function
local function make_complete(want_val)
	return function(arglead)
		local st = require("lazy-workspaces.state").read()
		local ws_counts = {}
		for _, ws_map in pairs(st) do
			if type(ws_map) == "table" then
				for ws_name, included in pairs(ws_map) do
					if included == want_val then
						ws_counts[ws_name] = (ws_counts[ws_name] or 0) + 1
					end
				end
			end
		end

		local out = {}
		local seen = {}
		for cfg, ws_map in pairs(st) do
			if type(ws_map) == "table" then
				for ws_name, included in pairs(ws_map) do
					if included == want_val then
						local key = cfg .. "\0" .. ws_name
						if not seen[key] then
							seen[key] = true
							local completion = ws_counts[ws_name] > 1 and (cfg .. "/" .. ws_name) or ws_name
							if completion:sub(1, #arglead) == arglead then
								out[#out + 1] = completion
							end
						end
					end
				end
			end
		end
		return out
	end
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

	local workspace_specs = M.collect({ configs = user_opts.configs })

	register_commands()

	-- Self-register so lazy manages lazy-workspaces (updates, UI, etc.)
	local self_spec = { dir = _self_path, name = "lazy-workspaces", lazy = false, priority = 1000 }
	local full_spec = vim.list_extend({ self_spec }, workspace_specs)

	local lazy_opts = user_opts.lazy or {}
	require("lazy").setup(vim.tbl_deep_extend("force", lazy_opts, { spec = full_spec }))
end

M._test = {
	self_path = function()
		return _self_path
	end,
}

return M
