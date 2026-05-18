#!/usr/bin/env bash
# new-setup.sh: create a fresh Neovim config pointing at your config repo.
#
# Usage:
#   bash new-setup.sh <github-repo-url> [out_dir]
#
# Example:
#   bash new-setup.sh git@github.com:user/nvim.conf.d.git
#   bash new-setup.sh https://github.com/user/nvim.conf.d /tmp/my-nvim

set -euo pipefail

REPO="${1:?Usage: new-setup.sh <github-repo-url> [out_dir]}"
OUT="${2:-/tmp/nvim}"
BRANCH="main"
TEMPLATE_URL="https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/${BRANCH}/template/init.lua"

if [ -d "$OUT" ]; then
  echo "Error: '$OUT' already exists. Remove it first or pass a different out_dir." >&2
  exit 1
fi

mkdir -p "$OUT"

curl -fsSL "$TEMPLATE_URL" \
  | sed \
      -e 's|"__MAPLEADER__"|" "|g' \
      -e 's|"__MAPLOCALLEADER__"|" "|g' \
      -e "s|\"file://__OUT_DIR__\"|\"${REPO}\"|g" \
      -e "s|__OUT_DIR__|${OUT}|g" \
      -e '/^[[:space:]]*-- __SPECS__/d' \
  > "$OUT/init.lua"

echo ""
echo "Created: $OUT/init.lua"
echo ""
echo "Test:    nvim -u $OUT/init.lua"
echo ""
echo "On first launch lazy-workspaces will clone your config repo and load workspaces."
