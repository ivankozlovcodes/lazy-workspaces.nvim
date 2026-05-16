local M = {}

---@class WorkspaceSource
---@field url string        file:// path or git URL
---@field branch string?    git branch (optional, defaults to repo default)
---@field enable string[]   workspace names to load

---@class LazyWorkspacesOpts
---@field workspaces WorkspaceSource[]

--- Resolve workspace sources, scan plugin specs, schedule workspace setup() calls.
--- Returns a flat list of lazy.nvim specs to pass to lazy.setup({ spec = ... }).
---@param opts LazyWorkspacesOpts
---@return table
function M.collect(opts)
  opts = opts or {}
  local resolver = require("lazy-workspaces.resolver")
  local specs = {}

  for _, ws_source in ipairs(opts.workspaces or {}) do
    local ok, path = pcall(resolver.resolve, ws_source.url, ws_source.branch)
    if not ok then
      vim.notify("[lazy-workspaces] could not resolve " .. tostring(ws_source.url) .. ": " .. tostring(path), vim.log.levels.ERROR)
    else
      if not vim.tbl_contains(vim.opt.rtp:get(), path) then
        vim.opt.rtp:append(path)
      end
      package.path = package.path
        .. ";" .. path .. "/lua/?.lua"
        .. ";" .. path .. "/lua/?/init.lua"

      for _, ws_name in ipairs(ws_source.enable or {}) do
        local plugins_dir = path .. "/lua/" .. ws_name .. "/plugins"
        if vim.fn.isdirectory(plugins_dir) == 1 then
          for _, file in ipairs(vim.fn.glob(plugins_dir .. "/*.lua", false, true)) do
            local chunk, err = loadfile(file)
            if not chunk then
              vim.notify("[lazy-workspaces] failed to load spec " .. file .. ": " .. tostring(err), vim.log.levels.WARN)
            else
              local ok2, spec = pcall(chunk)
              if ok2 and type(spec) == "table" then
                specs[#specs + 1] = spec
              end
            end
          end
        end

        vim.schedule(function()
          local ok3, mod = pcall(require, ws_name)
          if not ok3 then
            vim.notify("[lazy-workspaces] failed to load workspace '" .. ws_name .. "': " .. tostring(mod), vim.log.levels.WARN)
            return
          end
          if type(mod) == "table" and type(mod.setup) == "function" then
            local ok4, err = pcall(mod.setup)
            if not ok4 then
              vim.notify("[lazy-workspaces] workspace '" .. ws_name .. "' setup() error: " .. tostring(err), vim.log.levels.ERROR)
            end
          end
        end)
      end
    end
  end

  return specs
end

--- Called by lazy.nvim when the plugin is loaded. Registers the bootstrap command.
function M.setup()
  vim.api.nvim_create_user_command("LazyWorkspacesBootstrap", function(args)
    require("lazy-workspaces.bootstrap").command(args)
  end, { nargs = "*", desc = "Bootstrap nvim config to lazy-workspaces format", complete = "dir" })
end

return M
