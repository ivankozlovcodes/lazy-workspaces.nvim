local M = {}

--- Resolve a workspace source (local path or git URL) to an absolute local path.
---@param source string  absolute/~ path, git@, or https:// URL
---@param branch string?
---@return string
function M.resolve(source, branch)
  if source:match("^https?://") or source:match("^git@") then
    return M.resolve_git(source, branch)
  end
  -- local path (absolute or ~-prefixed)
  local path = vim.fn.expand(source)
  if vim.fn.isdirectory(path) == 0 then
    error("workspace path does not exist: " .. path)
  end
  return path
end

--- Clone or update a git repo, return local path.
---@param source string
---@param branch string?
---@return string
function M.resolve_git(source, branch)
  local name = source:match("/([^/]+)$"):gsub("%.git$", "")
  local dest = vim.fn.stdpath("data") .. "/lazy-workspaces/" .. name

  -- TODO: refresh (pull) on every nvim open, not just when repo is missing
  if vim.fn.isdirectory(dest) == 0 then
    vim.notify("[lazy-workspaces] cloning " .. source .. " ...", vim.log.levels.INFO)
    vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
    local cmd = { "git", "clone", "--filter=blob:none" }
    if branch then
      vim.list_extend(cmd, { "--branch", branch })
    end
    vim.list_extend(cmd, { source, dest })
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      error("git clone failed for " .. source .. ": " .. out)
    end
  else
    -- async pull so startup isn't blocked
    local cmd = { "git", "-C", dest, "pull", "--ff-only" }
    if branch then
      vim.list_extend(cmd, { "origin", branch })
    end
    vim.fn.jobstart(cmd, {
      on_exit = function(_, code)
        if code ~= 0 then
          vim.notify("[lazy-workspaces] git pull failed for " .. name, vim.log.levels.WARN)
        end
      end,
    })
  end

  return dest
end

return M
