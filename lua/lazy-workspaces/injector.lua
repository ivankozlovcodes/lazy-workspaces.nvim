local M = {}

--- Scan a workspace plugins/ dir, load each spec file, inject into lazy.nvim.
---@param ws_path string  absolute path to workspace repo root
---@param ws_name string  workspace name, e.g. "common"
function M.inject(ws_path, ws_name)
  local plugins_dir = ws_path .. "/lua/" .. ws_name .. "/plugins"

  if vim.fn.isdirectory(plugins_dir) == 0 then
    vim.notify("[lazy-workspaces] no plugins/ dir for workspace '" .. ws_name .. "' at " .. plugins_dir, vim.log.levels.DEBUG)
    return
  end

  -- 1. Load all spec files directly (avoids lazy module cache timing issues)
  local specs = {}
  for _, file in ipairs(vim.fn.glob(plugins_dir .. "/*.lua", false, true)) do
    local chunk, err = loadfile(file)
    if not chunk then
      vim.notify("[lazy-workspaces] failed to load spec " .. file .. ": " .. tostring(err), vim.log.levels.WARN)
    else
      local ok, spec = pcall(chunk)
      if ok and type(spec) == "table" then
        specs[#specs + 1] = spec
      end
    end
  end

  if #specs == 0 then
    return
  end

  local Config = require("lazy.core.config")
  local Plugin = require("lazy.core.plugin")
  local Loader = require("lazy.core.loader")
  local Handler = require("lazy.core.handler")

  -- 2. Parse specs into Config.spec (adds to meta, resolves fragments)
  Config.spec:parse(specs)

  -- 3. Sync any new plugins into Config.plugins
  for name, plugin in pairs(Config.spec.plugins) do
    if not Config.plugins[name] then
      Config.plugins[name] = plugin
    end
  end

  -- 4. Update install state so _.installed is set
  Plugin.update_state()

  -- TODO: figure out how to call lazy install on newly injected plugins
  -- (plugins not yet cloned won't load; user must run :Lazy install manually)

  -- 5. Activate: load start plugins immediately, register handlers for lazy ones
  for _, plugin in pairs(Config.plugins) do
    if not plugin._.loaded then
      if plugin.lazy == false then
        Loader.load(plugin, { start = "workspace" })
      else
        Handler.enable(plugin)
      end
    end
  end
end

return M
