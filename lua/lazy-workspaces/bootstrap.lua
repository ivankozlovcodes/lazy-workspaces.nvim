local M = {}

-- TODO: show before/after diff in a float before writing

local _plugin_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h:h")

local detect_workspaces = require("lazy-workspaces").detect_workspaces

local function strip_lazy_init(lines, ns)
	local mod_name = ns:gsub("/", ".") -- slash names → dot notation for require() pattern
	local out = {}
	for _, line in ipairs(lines) do
		if not line:match("require%([\"']" .. mod_name .. "%.lazy_init[\"']%)") then
			out[#out + 1] = line
		end
	end
	return out
end

local function wrap_in_setup(lines)
	while lines[#lines] == "" do
		lines[#lines] = nil
	end
	local out = { "local M = {}", "", "function M.setup()" }
	for _, line in ipairs(lines) do
		out[#out + 1] = line == "" and "" or "  " .. line
	end
	out[#out + 1] = "end"
	out[#out + 1] = ""
	out[#out + 1] = "return M"
	return out
end

local function transform_ns_init(ns_dir, ns)
	local path = ns_dir .. "/init.lua"
	if vim.fn.filereadable(path) == 0 then
		return "skipped (no init.lua)"
	end
	local lines = vim.fn.readfile(path)
	for _, l in ipairs(lines) do
		if l:match("function M%.setup") then
			return "skipped (already wrapped)"
		end
	end
	lines = strip_lazy_init(lines, ns)
	lines = wrap_in_setup(lines)
	vim.fn.writefile(lines, path)
	return "wrapped"
end

local function migrate_flat_plugins(lua_dir)
	local plugins_dir = lua_dir .. "/plugins"
	local specs_dir = plugins_dir .. "/plugins"
	local init_path = plugins_dir .. "/init.lua"
	local init_exists = vim.fn.filereadable(init_path) == 1

	vim.fn.mkdir(specs_dir, "p")
	local moved = {}
	for _, path in ipairs(vim.fn.glob(plugins_dir .. "/*.lua", false, true)) do
		local fname = vim.fn.fnamemodify(path, ":t")
		if fname ~= "init.lua" then
			vim.fn.rename(path, specs_dir .. "/" .. fname)
			moved[#moved + 1] = fname
		end
	end

	if init_exists then
		vim.notify("[lazy-workspaces] lua/plugins/init.lua already exists, skipping generation", vim.log.levels.WARN)
	else
		vim.fn.writefile({ "local M = {}", "", "function M.setup() end", "", "return M" }, init_path)
	end

	if #moved > 0 then
		vim.notify(
			"[lazy-workspaces] lua/plugins/*.lua moved to lua/plugins/plugins/. "
				.. 'If any spec file required another by name, update to require("plugins.plugins.X").',
			vim.log.levels.WARN
		)
	end

	return moved
end

local function write_config_init(config_dir)
	local init_path = config_dir .. "/init.lua"
	if vim.fn.filereadable(init_path) == 1 then
		vim.notify("[lazy-workspaces] lua/config/init.lua already exists, skipping generation", vim.log.levels.WARN)
		return "skipped"
	end

	local requires = {}
	for _, f in ipairs(vim.fn.glob(config_dir .. "/*.lua", false, true)) do
		local stem = vim.fn.fnamemodify(f, ":t:r")
		requires[#requires + 1] = '  require("config.' .. stem .. '")'
	end

	local lines = { "local M = {}", "", "function M.setup()" }
	vim.list_extend(lines, requires)
	vim.list_extend(lines, { "end", "", "return M" })
	vim.fn.writefile(lines, init_path)
	return "written"
end

local function disable_lazy_bootstrap_files(ns_dir)
	local moved = {}
	for _, path in ipairs(vim.fn.glob(ns_dir .. "/*.lua", false, true)) do
		local lines = vim.fn.readfile(path)
		for _, line in ipairs(lines) do
			if line:match("require%([\"']lazy[\"']%)%.setup") then
				local bak = path .. ".bak"
				vim.fn.rename(path, bak)
				moved[#moved + 1] = vim.fn.fnamemodify(path, ":t") .. " → " .. vim.fn.fnamemodify(bak, ":t")
				break
			end
		end
	end
	return moved
end

---@param out_dir string
---@param spec_dirs string[]?  defaults to {"plugins"} — only written when non-default
---@param dev boolean?  use init_dev.lua (local plugin path, no clone)
local function write_root_init(out_dir, spec_dirs, dev)
	local leader = vim.g.mapleader or "\\"
	local localleader = vim.g.maplocalleader or "\\"
	local function q(v)
		return v == "\\" and '"\\\\"' or '"' .. v .. '"'
	end

	local is_default = spec_dirs == nil or (#spec_dirs == 1 and spec_dirs[1] == "plugins")
	local specs_line
	if not is_default then
		local quoted = {}
		for _, d in ipairs(spec_dirs) do
			quoted[#quoted + 1] = '"' .. d .. '"'
		end
		specs_line = "\tspecs = { " .. table.concat(quoted, ", ") .. " },"
	end

	local template_name = dev and "init.dev.lua" or "init.lua"
	local template_path = _plugin_root .. "/template/" .. template_name
	local lines = vim.fn.readfile(template_path)
	local out = {}
	for _, line in ipairs(lines) do
		if line:match("^%s*%-%-%s*__SPECS__%s*$") then
			if specs_line then
				out[#out + 1] = specs_line
			end
		else
			line = line:gsub("__OUT_DIR__", function()
				return out_dir
			end)
			line = line:gsub('"__MAPLEADER__"', function()
				return q(leader)
			end)
			line = line:gsub('"__MAPLOCALLEADER__"', function()
				return q(localleader)
			end)
			line = line:gsub('"__PLUGIN_ROOT__"', function()
				return '"' .. _plugin_root .. '"'
			end)
			out[#out + 1] = line
		end
	end
	return out
end

--- Open a tab with old (left) vs new (right) init.lua in diff mode.
--- <CR> on the right buffer writes and calls on_confirm; q cancels.
--- Falls back to direct write in headless/non-interactive mode.
---@param init_path string
---@param new_lines string[]
---@param on_confirm function
local function show_diff(init_path, new_lines, on_confirm)
	if vim.v.vim_did_enter == 0 then
		vim.fn.writefile(new_lines, init_path)
		on_confirm()
		return
	end
	local old_lines = vim.fn.filereadable(init_path) == 1 and vim.fn.readfile(init_path) or {}

	local old_buf = vim.api.nvim_create_buf(false, true)
	local new_buf = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_lines(old_buf, 0, -1, false, old_lines)
	vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, new_lines)

	for _, buf in ipairs({ old_buf, new_buf }) do
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = "lua"
		vim.bo[buf].modifiable = false
	end
	vim.api.nvim_buf_set_name(old_buf, "init.lua [before]")
	vim.api.nvim_buf_set_name(new_buf, "init.lua [after]")

	vim.cmd("tabnew")
	vim.api.nvim_win_set_buf(0, old_buf)
	vim.cmd("diffthis")
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, new_buf)
	vim.cmd("diffthis")

	local function close_diff()
		if vim.api.nvim_buf_is_valid(old_buf) then
			vim.api.nvim_buf_delete(old_buf, { force = true })
		end
		if vim.api.nvim_buf_is_valid(new_buf) then
			vim.api.nvim_buf_delete(new_buf, { force = true })
		end
	end

	local opts = { buffer = new_buf, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		vim.fn.writefile(new_lines, init_path)
		close_diff()
		on_confirm()
	end, opts)
	vim.keymap.set("n", "q", function()
		close_diff()
		vim.notify("[lazy-workspaces] bootstrap cancelled", vim.log.levels.INFO)
	end, opts)

	vim.notify("[lazy-workspaces] <CR> write init.lua · q cancel", vim.log.levels.INFO)
end

local function write_root_init(out_dir, spec_dirs, dev)
	vim.fn.writefile(generate_root_init(out_dir, spec_dirs, dev), out_dir .. "/init.lua")
end

---@param args {args: string}
function M.command(args)
	local parts = vim.split(args.args, "%s+", { trimempty = true })

	local dev = false
	local filtered = {}
	for _, p in ipairs(parts) do
		if p == "--dev" then
			dev = true
		else
			filtered[#filtered + 1] = p
		end
	end
	parts = filtered

	local src_dir, out_dir

	if #parts == 0 then
		src_dir = vim.fn.stdpath("config")
		out_dir = "/tmp/nvim"
	elseif #parts == 1 then
		src_dir = vim.fn.expand(parts[1])
		out_dir = "/tmp/nvim"
	else
		src_dir = vim.fn.expand(parts[1])
		out_dir = vim.fn.expand(parts[2])
	end

	src_dir = vim.fn.fnamemodify(src_dir, ":p"):gsub("/$", "")
	out_dir = vim.fn.fnamemodify(out_dir, ":p"):gsub("/$", "")

	if vim.fn.isdirectory(src_dir) == 0 then
		vim.notify("[lazy-workspaces] src not found: " .. src_dir, vim.log.levels.ERROR)
		return
	end

	local confirm = vim.fn.confirm(
		string.format(
			"lazy-workspaces bootstrap\n\n  src: %s\n  out: %s\n\nCopy src → out and rewrite files. Proceed?",
			src_dir,
			out_dir
		),
		"&Yes\n&No",
		2
	)
	if confirm ~= 1 then
		vim.notify("[lazy-workspaces] bootstrap cancelled", vim.log.levels.INFO)
		return
	end

	vim.fn.mkdir(out_dir, "p")
	local cp_out = vim.fn.system({ "cp", "-r", src_dir .. "/.", out_dir })
	if vim.v.shell_error ~= 0 then
		vim.notify("[lazy-workspaces] copy failed: " .. cp_out, vim.log.levels.ERROR)
		return
	end

	local lua_dir = out_dir .. "/lua"
	if vim.fn.isdirectory(lua_dir) == 0 then
		vim.notify("[lazy-workspaces] no lua/ dir in source", vim.log.levels.ERROR)
		return
	end

	local namespaces = detect_workspaces(lua_dir)
	local results = {}

	if #namespaces == 0 then
		local has_plugins = vim.fn.isdirectory(lua_dir .. "/plugins") == 1
		local has_config = vim.fn.isdirectory(lua_dir .. "/config") == 1

		if not has_plugins and not has_config then
			vim.notify("[lazy-workspaces] no namespaces found under lua/", vim.log.levels.ERROR)
			return
		end

		if has_plugins then
			local moved = migrate_flat_plugins(lua_dir)
			results[#results + 1] = "plugins: moved specs(" .. #moved .. " files)"
		end
		if has_config then
			local res = write_config_init(lua_dir .. "/config")
			results[#results + 1] = "config: init(" .. res .. ")"
		end

		local loose = vim.fn.glob(lua_dir .. "/*.lua", false, true)
		if #loose > 0 then
			local names = {}
			for _, f in ipairs(loose) do
				names[#names + 1] = vim.fn.fnamemodify(f, ":t")
			end
			vim.notify(
				"[lazy-workspaces] orphaned files in lua/ not claimed by any workspace: " .. table.concat(names, ", "),
				vim.log.levels.WARN
			)
		end

		if has_config then
			namespaces[#namespaces + 1] = "config"
		end
		if has_plugins then
			namespaces[#namespaces + 1] = "plugins"
		end

		disable_lazy_bootstrap_files(out_dir)
	else
		for _, ns in ipairs(namespaces) do
			local ns_dir = lua_dir .. "/" .. ns
			local init_res = transform_ns_init(ns_dir, ns)
			local moved = disable_lazy_bootstrap_files(ns_dir)
			local moved_res = #moved > 0 and ("moved: " .. table.concat(moved, ", ")) or "no lazy bootstrap files"
			results[#results + 1] = ns .. ": init(" .. init_res .. "), " .. moved_res
		end
	end

	-- Detect spec dirs across all namespaces (any subdir with .lua files)
	local spec_dir_set = { plugins = true }
	for _, ns in ipairs(namespaces) do
		local ns_dir = lua_dir .. "/" .. ns
		for _, subdir in ipairs(vim.fn.glob(ns_dir .. "/*/", false, true)) do
			local dir_name = subdir:match("/([^/]+)/$")
			if dir_name and #vim.fn.glob(subdir .. "*.lua", false, true) > 0 then
				spec_dir_set[dir_name] = true
			end
		end
	end
	local spec_dirs = vim.tbl_keys(spec_dir_set)
	table.sort(spec_dirs)

	if #spec_dirs > 1 then
		results[#results + 1] = "spec dirs: " .. table.concat(spec_dirs, ", ")
	end

	write_root_init(out_dir, spec_dirs, dev)
	results[#results + 1] = "wrote init.lua" .. (dev and " (dev)" or "")

	local msg = "[lazy-workspaces] bootstrap → " .. out_dir .. "\n"
	for _, r in ipairs(results) do
		msg = msg .. "  • " .. r .. "\n"
	end
	msg = msg .. "\nTest: nvim -u " .. out_dir .. "/init.lua"
	vim.notify(msg, vim.log.levels.INFO)
end

M._test = {
	detect_workspaces = detect_workspaces,
	strip_lazy_init = strip_lazy_init,
	wrap_in_setup = wrap_in_setup,
	transform_ns_init = transform_ns_init,
	disable_lazy_bootstrap_files = disable_lazy_bootstrap_files,
	write_root_init = write_root_init,
	migrate_flat_plugins = migrate_flat_plugins,
	write_config_init = write_config_init,
}

return M
