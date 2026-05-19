local M = {}

function M.check()
	local h = vim.health
	local lw = require("lazy-workspaces")
	local opts = lw._get_opts()

	-- ── Prerequisites ─────────────────────────────────────────────────────────
	h.start("lazy-workspaces")

	h.info("version: " .. (lw.version or "unknown"))

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
	h.info("version: " .. (lw.version or "unknown"))

	local state_mod = require("lazy-workspaces.state")
	local json_path = state_mod.path()
	if vim.fn.filereadable(json_path) == 1 then
		h.info("state: " .. json_path)
	else
		h.warn("state file not found: " .. json_path .. " (created on first launch)")
	end

	local scan_cache = lw._get_scan_cache()
	if not scan_cache then
		h.warn("collect() not yet run — remaining checks skipped")
		return
	end

	local state = state_mod.read()
	local spec_dirs = opts.specs or { "plugins" }
	local spec_entries = {}

	-- ── Configs ───────────────────────────────────────────────────────────────
	for cfg_name, result in pairs(scan_cache) do
		h.start(cfg_name .. "  (" .. result.path .. ")")

		local ws_state = state[cfg_name] or {}
		local COL = 10
		local fmt = ("%%-%ds %%s"):format(COL)

		if #result.workspaces == 0 and #result.specs == 0 then
			h.warn("no workspaces or spec dirs found under lua/")
		end

		local on_disk = {}
		for _, ws in ipairs(result.workspaces) do
			on_disk[ws] = true
			local has_init = vim.fn.filereadable(result.path .. "/lua/" .. ws .. "/init.lua") == 1
			if ws_state[ws] == false then
				h.info(fmt:format("[excluded]", ws))
			elseif not has_init then
				h.warn(ws .. " — no init.lua")
			else
				h.info(fmt:format("OK", ws))
				for _, sd in ipairs(spec_dirs) do
					local dir = result.path .. "/lua/" .. ws .. "/" .. sd
					if vim.fn.isdirectory(dir) == 1 then
						spec_entries[#spec_entries + 1] = {
							label = cfg_name .. "  " .. ws .. "  " .. sd,
							dir = dir,
							count = #vim.fn.glob(dir .. "/*.lua", false, true),
						}
					end
				end
			end
		end

		for ws in pairs(ws_state) do
			if not on_disk[ws] then
				h.warn(ws .. " — stale, not on disk")
			end
		end

		for _, ns in ipairs(result.specs) do
			local count = ns.via_init and #vim.fn.glob(ns.path .. "/*.lua", false, true)
				or #vim.fn.glob(ns.path .. "/*.lua", false, true)
			local how = ns.via_init and "via init.lua" or "individual files"
			spec_entries[#spec_entries + 1] = {
				label = cfg_name .. " " .. ns.name,
				dir = ns.path,
				count = count,
				note = how,
			}
		end
	end

	-- stale config keys: in JSON but not in scan_cache
	for cfg_key in pairs(state) do
		if not scan_cache[cfg_key] then
			h.start(cfg_key)
			h.warn("stale — no matching config in setup()")
		end
	end

	-- ── Spec paths ────────────────────────────────────────────────────────────
	if #spec_entries > 0 then
		h.start("lazy-workspaces: spec paths")
		local max_w = 0
		for _, e in ipairs(spec_entries) do
			max_w = math.max(max_w, #e.label)
		end
		local fmt = ("%%-%ds  %%s  (%%d specs)"):format(max_w)
		for _, e in ipairs(spec_entries) do
			local line = fmt:format(e.label, e.dir, e.count)
			if e.note then
				line = line .. "  [" .. e.note .. "]"
			end
			h.info(line)
		end
	end
end

return M
