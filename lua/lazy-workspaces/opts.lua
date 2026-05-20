local M = {}

---@class WorkspaceSource
---@field source string
---@field branch string?

--- Extract source and branch from a config value.
---@param value string|WorkspaceSource
---@return string, string|nil
function M.parse_source(value)
	if type(value) == "string" then
		return value, nil
	elseif type(value) == "table" then
		return value.source, value.branch
	end
	error("invalid workspace source type: " .. type(value))
end

--- Derive a human-readable config name from a source URL or path.
---   /tmp/nvim                     → /tmp/nvim
---   git@github.com:user/repo.git  → user/repo
---   https://github.com/user/repo  → user/repo
---@param source string
---@return string
function M.name_from_source(source)
	local ssh_path = source:match("^git@[^:]+:(.+)$")
	if ssh_path then
		return ssh_path:gsub("%.git$", "")
	end
	if source:match("^https?://") then
		local two_seg = source:match("([^/]+/[^/]+)$")
		if two_seg then
			return two_seg:gsub("%.git$", "")
		end
	end
	return source
end

--- Normalize opts.configs into a flat list of { name, source, branch } entries.
--- Accepts both array form (ordered list) and dict form (name-keyed table).
---@param configs table
---@return table[]  list of { name: string, source: string, branch: string|nil }
function M.normalize(configs)
	local out = {}
	if configs[1] ~= nil then
		for _, v in ipairs(configs) do
			if type(v) == "table" then
				out[#out + 1] = {
					name   = v.name or M.name_from_source(v.source),
					source = v.source,
					branch = v.branch,
				}
			else
				out[#out + 1] = { name = M.name_from_source(v), source = v, branch = nil }
			end
		end
	else
		for k, v in pairs(configs) do
			local src, branch = M.parse_source(v)
			out[#out + 1] = { name = k, source = src, branch = branch }
		end
	end
	return out
end

---@type LazyWorkspacesOpts
M.defaults = {
	specs     = { "plugins" },
	auto_pull = true,
}

--- Return opts with defaults applied. Explicit false is preserved (vim.tbl_deep_extend "keep").
---@param opts LazyWorkspacesOpts?
---@return LazyWorkspacesOpts
function M.apply_defaults(opts)
	return vim.tbl_deep_extend("keep", opts or {}, M.defaults)
end

--- Compute the local filesystem path for a config entry without triggering a git pull.
---@param entry table  { source: string, branch: string|nil }
---@return string
function M.local_path_for(entry)
	if entry.source:match("^https?://") or entry.source:match("^git@") then
		local dest_name = entry.source:match("/([^/]+)$"):gsub("%.git$", "")
		return vim.fn.stdpath("data") .. "/lazy-workspaces/" .. dest_name
	end
	return vim.fn.expand(entry.source)
end

return M
