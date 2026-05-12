local M = {}

--- Resolve a workspace URL to an absolute local filesystem path.
---@param url string
---@param branch string?
---@return string
function M.resolve(url, branch)
  if url:sub(1, 7) == "file://" then
    local path = vim.fn.expand(url:sub(8))
    if vim.fn.isdirectory(path) == 0 then
      error("workspace path does not exist: " .. path)
    end
    return path
  end

  if url:sub(1, 8) == "https://" or url:sub(1, 4) == "git@" then
    return M.resolve_git(url, branch)
  end

  error("unsupported URL scheme: " .. url)
end

--- Clone or update a git repo, return local path.
---@param url string
---@param branch string?
---@return string
function M.resolve_git(url, branch)
  local name = url:match("/([^/]+)$"):gsub("%.git$", "")
  local dest = vim.fn.stdpath("data") .. "/lazy-workspaces/" .. name

  -- TODO: refresh (pull) on every nvim open, not just when repo is missing
  if vim.fn.isdirectory(dest) == 0 then
    vim.notify("[lazy-workspaces] cloning " .. url .. " ...", vim.log.levels.INFO)
    vim.fn.mkdir(vim.fn.fnamemodify(dest, ":h"), "p")
    local cmd = { "git", "clone", "--filter=blob:none" }
    if branch then
      vim.list_extend(cmd, { "--branch", branch })
    end
    vim.list_extend(cmd, { url, dest })
    local out = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
      error("git clone failed for " .. url .. ": " .. out)
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
