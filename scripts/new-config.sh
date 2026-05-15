#!/usr/bin/env bash
# new-config.sh: scaffold a minimal Neovim config with lazy-workspaces.
#
# Usage:
#   bash <(curl -s https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/main/scripts/new-config.sh)
#   bash new-config.sh [out_dir]

set -euo pipefail

OUT_DIR="${1:-/tmp/lazy-workspaces.conf.d}"
mkdir -p "$OUT_DIR"

cat > "$OUT_DIR/init.lua" <<'EOF'
vim.g.mapleader = " "
vim.g.maplocalleader = " "

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local out = vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({ { "Failed to clone lazy.nvim:\n", "ErrorMsg" }, { out, "WarningMsg" } }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    {
      "ivankozlovcodes/lazy-workspaces.nvim",
      lazy = false,
      priority = 1000,
      opts = { workspaces = {} },
    },
  },
  change_detection = { notify = false },
})
EOF

echo "Scaffolded: $OUT_DIR/init.lua"
echo ""
echo "Test: nvim -u $OUT_DIR/init.lua"
echo "Then run :LazyWorkspacesBootstrap to migrate an existing config."
