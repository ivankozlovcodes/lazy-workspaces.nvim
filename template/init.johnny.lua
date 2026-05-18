-- migrated from ~/git/neovim-config (old lazy-workspaces API)
-- test: nvim -u ~/git/lazy-workspaces.nvim/template/johnny.init.lua
--
-- curl -fsSL https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/feat-commands/template/init.johnny.lua -o ~/.config/nvim/init.lua
--
-- After first launch, vscode workspace will be auto-included.
-- Run :LazyWorkspacesExclude vscode to exclude it (was not in old enable list).

vim.g.mapleader = " "
vim.g.maplocalleader = " "

local lwpath = vim.fn.stdpath("data") .. "/lazy/lazy-workspaces.nvim"
if not (vim.uv or vim.loop).fs_stat(lwpath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/ivankozlovcodes/lazy-workspaces.nvim.git",
		lwpath,
	})
end
vim.opt.rtp:prepend(lwpath)

require("lazy-workspaces").setup({
	configs = {
		neovim_config = { source = "git@github.com:JohnnyJumper/neovim-config.git" },
	},
	lazy = {
		rocks = { hererocks = true },
		change_detection = { notify = false },
	},
})
