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

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none", "--branch=stable",
    "https://github.com/folke/lazy.nvim.git", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

-- Bootstrap lazy-workspaces
local lwpath = vim.fn.stdpath("data") .. "/lazy/lazy-workspaces.nvim"
if not (vim.uv or vim.loop).fs_stat(lwpath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/ivankozlovcodes/lazy-workspaces.nvim.git", lwpath,
  })
end
vim.opt.rtp:prepend(lwpath)

local workspace_specs = {}
if (vim.uv or vim.loop).fs_stat(lwpath) then
  workspace_specs = require("lazy-workspaces").collect({
    workspaces = {},
  })
end

require("lazy").setup({
  spec = vim.list_extend(workspace_specs, {
    { "ivankozlovcodes/lazy-workspaces.nvim", lazy = false, opts = {} },
  }),
  change_detection = { notify = false },
})
EOF

echo "Scaffolded: $OUT_DIR/init.lua"
echo ""
echo "Test: nvim -u $OUT_DIR/init.lua"
echo "Then run :LazyWorkspacesBootstrap to migrate an existing config."
