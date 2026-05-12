#!/usr/bin/env bash
# bootstrap.sh: migrate a standard nvim config to lazy-workspaces format.
#
# What it does:
#   1. Detects the namespace (lua/<ns>/init.lua)
#   2. Renames lua/<ns>/lazy/ → lua/<ns>/plugins/  (if present)
#   3. Wraps lua/<ns>/init.lua body in M.setup() and removes lazy_init require
#   4. Replaces top-level init.lua with a lazy-workspaces bootstrap
#
# Usage:
#   ./bootstrap.sh [nvim-config-dir]
#   ./bootstrap.sh ~/.config/nvim

set -euo pipefail

CONFIG_DIR="${1:-$HOME/.config/nvim}"
CONFIG_DIR="$(realpath "$CONFIG_DIR")"
LUA_DIR="$CONFIG_DIR/lua"

# ── helpers ──────────────────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo "  → $*"; }

backup() {
  local src="$1"
  local bak="${src}.bak"
  cp "$src" "$bak"
  info "backed up $src → $bak"
}

# ── 1. detect namespace ───────────────────────────────────────────────────────

[ -d "$LUA_DIR" ] || die "no lua/ directory found in $CONFIG_DIR"

NAMESPACES=()
for d in "$LUA_DIR"/*/; do
  [ -f "${d}init.lua" ] && NAMESPACES+=("$(basename "$d")")
done

case "${#NAMESPACES[@]}" in
  0) die "no lua/<ns>/init.lua found under $LUA_DIR" ;;
  1) NS="${NAMESPACES[0]}" ;;
  *)
    echo "Multiple namespaces found: ${NAMESPACES[*]}"
    read -r -p "Which namespace to migrate? " NS
    [[ " ${NAMESPACES[*]} " == *" $NS "* ]] || die "unknown namespace: $NS"
    ;;
esac

NS_DIR="$LUA_DIR/$NS"
info "namespace: $NS"

# ── 2. rename plugin dir ──────────────────────────────────────────────────────

PLUGIN_DIR=""
for candidate in "lazy" "plugins"; do
  [ -d "$NS_DIR/$candidate" ] && PLUGIN_DIR="$candidate" && break
done

if [ -z "$PLUGIN_DIR" ]; then
  info "no lazy/ or plugins/ dir found under $NS_DIR — skipping rename"
elif [ "$PLUGIN_DIR" = "lazy" ]; then
  mv "$NS_DIR/lazy" "$NS_DIR/plugins"
  info "renamed $NS_DIR/lazy → $NS_DIR/plugins"
else
  info "plugins/ dir already exists — skipping rename"
fi

# ── 3. transform lua/<ns>/init.lua ───────────────────────────────────────────

NS_INIT="$NS_DIR/init.lua"
[ -f "$NS_INIT" ] || die "$NS_INIT not found"

# check if already wrapped
if grep -q "function M.setup" "$NS_INIT"; then
  info "$NS_INIT already has M.setup() — skipping transform"
else
  backup "$NS_INIT"

  # strip lazy_init require line, wrap body in M.setup()
  BODY=$(grep -v "require(\"${NS}\.lazy_init\")" "$NS_INIT" | \
         grep -v "require('${NS}\.lazy_init')")

  cat > "$NS_INIT" <<EOF
local M = {}

function M.setup()
${BODY}
end

return M
EOF

  # indent the body (basic: prepend two spaces to non-empty lines)
  python3 - "$NS_INIT" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()

out = []
inside = False
for line in lines:
    stripped = line.rstrip('\n')
    if stripped == 'function M.setup()':
        inside = True
        out.append(stripped + '\n')
    elif stripped == 'end' and inside:
        inside = False
        out.append(stripped + '\n')
    elif inside and stripped != '':
        out.append('  ' + stripped + '\n')
    else:
        out.append(line)

with open(path, 'w') as f:
    f.writelines(out)
PYEOF

  info "wrapped $NS_INIT in M.setup()"
fi

# ── 4. replace top-level init.lua ────────────────────────────────────────────

TOP_INIT="$CONFIG_DIR/init.lua"
[ -f "$TOP_INIT" ] && backup "$TOP_INIT"

cat > "$TOP_INIT" <<EOF
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Bootstrap lazy.nvim
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
      "ivankozlov/lazy-workspaces",
      lazy = false,
      priority = 1000,
      opts = {
        workspaces = {
          {
            url = "file://$CONFIG_DIR",
            enable = { "$NS" },
          },
        },
      },
    },
  },
  change_detection = { notify = false },
})
EOF

info "wrote new $TOP_INIT"

# ── done ─────────────────────────────────────────────────────────────────────

echo ""
echo "Done. Review changes:"
echo "  $TOP_INIT"
echo "  $NS_INIT"
[ -n "$PLUGIN_DIR" ] && [ "$PLUGIN_DIR" = "lazy" ] && \
  echo "  $NS_DIR/plugins/  (was lazy/)"
echo ""
echo "Original files backed up as *.bak"
echo "You may also remove $NS_DIR/lazy_init.lua if it exists."
