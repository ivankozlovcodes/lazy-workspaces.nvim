local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- Must be set before lazy loads any plugin
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Isolate lazy data from main nvim install
local lazypath = repo .. "/.sandbox/lazy/lazy.nvim"
vim.env.LAZY = repo .. "/.sandbox/lazy"

if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		{
			dir = repo,
			name = "lazy-workspaces",
			lazy = false,
			priority = 1000,
			opts = {
				workspaces = {
					{
						url = "git@github.com:ivankozlovcodes/nvim.conf.d.git",
						branch = "pluginize",
						enable = { "common", "personal" },
					},
				},
			},
		},
	},
})
