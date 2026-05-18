local M = {}

local _path = nil

function M.path()
	return _path or (vim.fn.stdpath("config") .. "/lazy-workspaces.json")
end

function M._set_path(p)
	_path = p
end

function M._reset_path()
	_path = nil
end

--- Returns {} if file is missing or malformed (emits WARN on malformed).
---@return table<string, table<string, boolean>>
function M.read()
	local p = M.path()
	if vim.fn.filereadable(p) == 0 then
		return {}
	end
	local lines = vim.fn.readfile(p)
	local raw = table.concat(lines, "\n")
	local ok, result = pcall(vim.json.decode, raw)
	if not ok or type(result) ~= "table" then
		vim.notify(
			"[lazy-workspaces] could not parse " .. p .. ": " .. tostring(result),
			vim.log.levels.WARN
		)
		return {}
	end
	return result
end

---@param state table<string, table<string, boolean>>
---@return string
local function pretty_encode(state)
	local cfg_keys = vim.tbl_keys(state)
	table.sort(cfg_keys)
	if #cfg_keys == 0 then
		return "{}"
	end
	local lines = {"{"}
	for i, cfg in ipairs(cfg_keys) do
		local ws_map = state[cfg]
		local ws_keys = vim.tbl_keys(ws_map)
		table.sort(ws_keys)
		local cfg_comma = i < #cfg_keys and "," or ""
		if #ws_keys == 0 then
			lines[#lines + 1] = "  " .. vim.json.encode(cfg) .. ": {}" .. cfg_comma
		else
			lines[#lines + 1] = "  " .. vim.json.encode(cfg) .. ": {"
			for j, ws in ipairs(ws_keys) do
				local ws_comma = j < #ws_keys and "," or ""
				lines[#lines + 1] = "    " .. vim.json.encode(ws) .. ": " .. (ws_map[ws] and "true" or "false") .. ws_comma
			end
			lines[#lines + 1] = "  }" .. cfg_comma
		end
	end
	lines[#lines + 1] = "}"
	return table.concat(lines, "\n")
end

--- Writes nested state table as pretty-printed JSON. Emits ERROR on write failure.
---@param state table<string, table<string, boolean>>
function M.write(state)
	local p = M.path()
	local encoded = pretty_encode(state)
	local ret = vim.fn.writefile(vim.split(encoded, "\n"), p)
	if ret ~= 0 then
		vim.notify("[lazy-workspaces] failed to write " .. p, vim.log.levels.ERROR)
	end
end

--- Reconcile JSON state against discovered configs/workspaces.
--- configs: { config_name = [ws_name, ...] }
--- Rules:
---   config/ws not in JSON  → add as true, mark dirty
---   config/ws in JSON      → keep value
---   JSON config/ws not in input → keep key (surfaced by :checkhealth)
--- Saves if dirty. Returns { config_name = { ws_name = bool } } for all input entries.
---@param configs table<string, string[]>
---@return table<string, table<string, boolean>>
function M.reconcile(configs)
	local state = M.read()
	local dirty = false

	local known = {}
	for cfg, ws_names in pairs(configs) do
		for _, ws_name in ipairs(ws_names) do
			known[cfg .. "\0" .. ws_name] = true
		end
	end

	for cfg, ws_names in pairs(configs) do
		if not state[cfg] then
			state[cfg] = {}
		end
		for _, ws_name in ipairs(ws_names) do
			if state[cfg][ws_name] == nil then
				state[cfg][ws_name] = true
				dirty = true
			end
		end
	end

	-- stale entries are surfaced by :checkhealth lazy-workspaces, not at startup

	if dirty then
		M.write(state)
	end

	local effective = {}
	for cfg, ws_names in pairs(configs) do
		effective[cfg] = {}
		for _, ws_name in ipairs(ws_names) do
			effective[cfg][ws_name] = state[cfg][ws_name]
		end
	end
	return effective
end

return M
