vim.opt.rtp:prepend(vim.fn.getcwd())

local plenary = vim.env.PLENARY_PATH
	or vim.fn.expand("~/.local/share/nvim/lazy/plenary.nvim")
if vim.fn.isdirectory(plenary) == 1 then
	vim.opt.rtp:prepend(plenary)
end
