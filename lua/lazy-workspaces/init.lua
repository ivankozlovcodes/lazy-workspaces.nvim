local M = {}

---@class WorkspaceSource
---@field url string        file:// path or git URL
---@field enable string[]   workspace names to load

---@class LazyWorkspacesOpts
---@field workspaces WorkspaceSource[]

---@param opts LazyWorkspacesOpts
function M.setup(opts)
  opts = opts or {}
  for _, ws_source in ipairs(opts.workspaces or {}) do
    local ok, err = pcall(M._load_source, ws_source)
    if not ok then
      vim.notify("[lazy-workspaces] " .. tostring(err), vim.log.levels.ERROR)
    end
  end
end

---@param ws_source WorkspaceSource
function M._load_source(ws_source)
  local resolver = require("lazy-workspaces.resolver")
  local path = resolver.resolve(ws_source.url)

  -- Add repo root to rtp so lua/ inside it is searchable
  vim.opt.rtp:append(path)
  package.path = package.path
    .. ";" .. path .. "/lua/?.lua"
    .. ";" .. path .. "/lua/?/init.lua"

  for _, ws_name in ipairs(ws_source.enable or {}) do
    M._load_workspace(ws_name)
  end
end

---@param ws_name string  e.g. "common"
function M._load_workspace(ws_name)
  local ok, mod = pcall(require, ws_name)
  if not ok then
    vim.notify("[lazy-workspaces] failed to load workspace '" .. ws_name .. "': " .. tostring(mod), vim.log.levels.WARN)
    return
  end
  if type(mod) == "table" and type(mod.setup) == "function" then
    mod.setup()
  end
end

return M
