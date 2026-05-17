local H = {}

-- files: { ["rel/path"] = "content\nline2", ... }
function H.make_tree(files)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  for rel, content in pairs(files) do
    local abs = root .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ":h"), "p")
    vim.fn.writefile(vim.split(content, "\n"), abs)
  end
  return root
end

function H.cleanup(path)
  vim.fn.system({ "rm", "-rf", path })
end

function H.file_exists(path)
  return vim.fn.filereadable(path) == 1
end

function H.dir_exists(path)
  return vim.fn.isdirectory(path) == 1
end

function H.content_has(path, pattern)
  for _, line in ipairs(vim.fn.readfile(path)) do
    if line:match(pattern) then
      return true
    end
  end
  return false
end

function H.content_lacks(path, pattern)
  return not H.content_has(path, pattern)
end

return H
