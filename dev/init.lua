local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

-- Must be set before lazy loads any plugin
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Sandbox: isolate lazy data and bootstrap lazy.nvim into sandbox dir.
-- setup() detects lazy is already on rtp and skips its internal bootstrap.
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

-- lazy-workspaces is already on rtp (repo = plugin root)
vim.opt.rtp:prepend(repo)

require("lazy-workspaces").setup({
	configs = {
		{
			url = "git@github.com:ivankozlovcodes/nvim.conf.d.git",
			branch = "pluginize",
			enable = { "common", "personal" },
		},
	},
})
