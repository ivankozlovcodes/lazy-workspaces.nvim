local M = {}

local function name_from_source(source)
	local ssh = source:match("^git@[^:]+:(.+)$")
	if ssh then
		return ssh:gsub("%.git$", "")
	end
	if source:match("^https?://") then
		local two = source:match("([^/]+/[^/]+)$")
		if two then
			return two:gsub("%.git$", "")
		end
	end
	return source
end

function M.check()
	local h = vim.health
	local lw = require("lazy-workspaces")
	local opts = lw._get_opts()

	-- ── Prerequisites (one line each) ─────────────────────────────────────────
	h.start("lazy-workspaces")

	if vim.fn.has("nvim-0.10") == 0 then
		h.error("Neovim >= 0.10 required")
	end
	if not pcall(require, "lazy") then
		h.error("lazy.nvim not found")
	end

	if not opts then
		h.warn("setup() not called — remaining checks skipped")
		return
	end
	h.ok("setup() called")

	local state_mod = require("lazy-workspaces.state")
	local json_path = state_mod.path()
	if vim.fn.filereadable(json_path) == 1 then
		h.info("state: " .. json_path)
	else
		h.warn("state file not found: " .. json_path .. " (created on first launch)")
	end
	local state = state_mod.read()

	-- ── Configs ───────────────────────────────────────────────────────────────
	local resolver = require("lazy-workspaces.resolver")
	local spec_dirs = opts.specs or { "plugins" }
	local named_configs = {}

	for k, v in pairs(opts.configs or {}) do
		local name
		if type(k) == "string" then
			name = k
		else
			local src = type(v) == "string" and v or (type(v) == "table" and v.source or tostring(k))
			name = name_from_source(src)
		end
		named_configs[name] = v
	end

	if vim.tbl_isempty(named_configs) then
		h.warn("no configs defined")
		return
	end

	local spec_entries = {} -- collected for the spec paths section

	for cfg_name, value in pairs(named_configs) do
		local source = type(value) == "string" and value or value.source
		local ok, local_path = pcall(resolver.resolve, source, type(value) == "table" and value.branch or nil)

		if not ok then
			h.start(cfg_name)
			h.error("resolve failed — " .. tostring(local_path))
		else
			h.start(cfg_name .. "  (" .. local_path .. ")")

			local ws_names = lw.detect_workspaces(local_path .. "/lua")
			local ws_state = state[cfg_name] or {}

			if #ws_names == 0 then
				h.warn("no workspaces found under lua/")
			end

			local COL = 10 -- width of "[excluded]"
			local fmt = ("%%-%ds %%s"):format(COL)

			local on_disk = {}
			for _, ws in ipairs(ws_names) do
				on_disk[ws] = true
				if ws_state[ws] == false then
					h.info(fmt:format("[excluded]", ws))
				else
					h.info(fmt:format("OK", ws))
					for _, sd in ipairs(spec_dirs) do
						local dir = local_path .. "/lua/" .. ws .. "/" .. sd
						if vim.fn.isdirectory(dir) == 1 then
							local n = #vim.fn.glob(dir .. "/*.lua", false, true)
							spec_entries[#spec_entries + 1] = {
								label = cfg_name .. "  " .. ws .. "  " .. sd,
								dir = dir,
								count = n,
							}
						end
					end
				end
			end

			for ws in pairs(ws_state) do
				if not on_disk[ws] then
					h.warn(ws .. " No such directory " .. local_path .. "/lua/" .. ws)
				end
			end
		end
	end

	-- stale config keys: in JSON but not in opts
	for cfg_key in pairs(state) do
		if not named_configs[cfg_key] then
			h.start(cfg_key)
			h.warn("stale — no matching config in setup()")
		end
	end

	-- spec paths section
	if #spec_entries > 0 then
		h.start("lazy-workspaces: spec paths")
		local max_w = 0
		for _, e in ipairs(spec_entries) do
			max_w = math.max(max_w, #e.label)
		end
		local fmt = ("%%-%ds  %%s  (%%d specs)"):format(max_w)
		for _, e in ipairs(spec_entries) do
			h.info(fmt:format(e.label, e.dir, e.count))
		end
	end
end

return M
