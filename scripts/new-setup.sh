#!/usr/bin/env bash
# new-setup.sh: create a fresh Neovim config pointing at your config repo.
#
# Usage:
#   bash new-setup.sh <github-repo-url> [out_dir]
#
#
#   bash new-setup.sh git@github.com:user/nvim.conf.d.git
#   bash new-setup.sh https://github.com/user/nvim.conf.d /tmp/my-nvim

set -euo pipefail

REPO="${1:-}"
OUT="${2:-/tmp/nvim}"
BRANCH="feat/setup"
TEMPLATE_URL="https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/${BRANCH}/template/init.lua"

if [ -d "$OUT" ]; then
  echo "Error: '$OUT' already exists. Remove it first or pass a different out_dir." >&2
  exit 1
fi

mkdir -p "$OUT"

TEMPLATE=$(curl -fsSL "$TEMPLATE_URL")

if [ -n "$REPO" ]; then
  echo "$TEMPLATE" | sed \
    -e 's|"__MAPLEADER__"|" "|g' \
    -e 's|"__MAPLOCALLEADER__"|" "|g' \
    -e "s|source = \"__OUT_DIR__\"|source = \"${REPO}\"|" \
    -e "s|__OUT_DIR__|${OUT}|g" \
    -e '/^[[:space:]]*-- __SPECS__/d' \
    > "$OUT/init.lua"
else
  echo "$TEMPLATE" | sed \
    -e 's|"__MAPLEADER__"|" "|g' \
    -e 's|"__MAPLOCALLEADER__"|" "|g' \
    -e '/source = "__OUT_DIR__"/d' \
    -e "s|__OUT_DIR__|${OUT}|g" \
    -e '/^[[:space:]]*-- __SPECS__/d' \
    > "$OUT/init.lua"
fi

echo ""
echo "Created: $OUT/init.lua"
echo ""
echo "Test:    nvim -u $OUT/init.lua"
echo ""
echo "On first launch lazy-workspaces will clone your config repo and load workspaces."
