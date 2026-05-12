local M = {}

--- Resolve a workspace URL to an absolute local filesystem path.
---@param url string
---@return string
function M.resolve(url)
  if url:sub(1, 7) == "file://" then
    local path = vim.fn.expand(url:sub(8))
    if vim.fn.isdirectory(path) == 0 then
      error("workspace path does not exist: " .. path)
    end
    return path
  end
  error("unsupported URL scheme (only file:// supported): " .. url)
end

return M
