# lazy-workspaces.nvim

Split your Neovim config into modular **workspaces** — each with its own options, keymaps, and plugins — loaded automatically by [lazy.nvim](https://github.com/folke/lazy.nvim).

## Philosophy

Most Neovim configs grow into monoliths: everything merged into one repo, enabled everywhere, managed by commenting lines in and out. lazy-workspaces treats your config like a monorepo of independent modules.

Each **workspace** is a self-contained folder with its own `init.lua` (options, keymaps, autocmds) and `plugins/` directory (lazy.nvim specs). Workspaces can live in one repo or many, on a local path or a remote git repo. You include or exclude them per-machine without touching the source.

Which workspaces are active is tracked in `lazy-workspaces.json` — separate from the workspace code itself, kept out of your config repo, managed via commands.

## Requirements

- Neovim 0.10+

---

## Getting Started

The fastest path: run `:LazyWorkspacesBootstrap` from your existing Neovim session. It migrates your current config to lazy-workspaces format and writes the result to `/tmp/nvim`.

Test it:

```bash
nvim -u /tmp/nvim/init.lua
```

Happy? Move it into place:

```bash
mv ~/.config/nvim ~/.config/nvim.bak && mv /tmp/nvim ~/.config/nvim
```

> **Warning:** Back up first, or keep your config in git. lazy-workspaces supports git URLs — your workspaces can live in a repo and be pulled automatically on every start.

---

## Workspace Structure

Each workspace is a folder under `lua/` with an `init.lua` exposing `M.setup()` and one or more spec directories (default: `plugins/`):

```
nvim.conf.d/
  lua/
    common/
      init.lua        ← M.setup(): options, keymaps, autocmds
      plugins/
        treesitter.lua
        blink.lua
    personal/
      init.lua
      plugins/
        lazygit.lua
    work/
      init.lua
      plugins/
        copilot.lua
```

`init.lua` shape:

```lua
local M = {}

function M.setup()
  vim.opt.number = true
  vim.keymap.set("n", "<leader>q", "<cmd>q<cr>")
end

return M
```

Plugin spec files follow the standard lazy.nvim format:

```lua
-- lua/common/plugins/treesitter.lua
return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  opts = {},
}
```

---

## Configuration

`setup(opts)` is the single entry point. It bootstraps lazy.nvim, resolves workspace sources, loads specs, and schedules each workspace's `M.setup()`. You do not call `lazy.setup()` yourself.

```lua
-- ~/.config/nvim/init.lua
local lwpath = vim.fn.stdpath("data") .. "/lazy/lazy-workspaces.nvim"
if not (vim.uv or vim.loop).fs_stat(lwpath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/ivankozlovcodes/lazy-workspaces.nvim.git", lwpath,
  })
end
vim.opt.rtp:prepend(lwpath)

require("lazy-workspaces").setup({
  configs = {
    personal = { source = "/home/user/git/nvim.conf.d" },
    work     = { source = "git@github.com:corp/work-nvim.git", branch = "stable" },
  },
})
```

### `configs`

Maps a config name to a workspace source. The name becomes the key in `lazy-workspaces.json`.

```lua
configs = {
  -- explicit name
  personal = { source = "/home/user/git/nvim.conf.d" },
  -- array style — name derived from source
  { source = "git@github.com:user/nvim.conf.d.git" },
}
```

**URL schemes:**

| URL | Behavior |
|---|---|
| `/abs/path` or `~/rel/path` | Load from local directory |
| `git@github.com:user/repo.git` | Clone on first start, pull on subsequent starts |
| `https://github.com/user/repo` | Same |

**Name derivation** (array-style configs without explicit name):

| URL | Derived name |
|---|---|
| `git@github.com:user/repo.git` | `user/repo` |
| `https://github.com/user/repo.git` | `user/repo` |

### `specs`

Subdirectory names to scan for lazy.nvim spec files. Default: `{ "plugins" }`.

```lua
specs = { "plugins", "themes" }
```

`:LazyWorkspacesBootstrap` auto-detects all subdirectories containing `.lua` files inside each workspace and populates `specs` accordingly. **Every `.lua` file in a listed directory is executed and its return value passed to `lazy.setup()` as a spec** — so only list directories that exclusively contain lazy.nvim spec files. Remove any auto-detected entries that point to non-spec directories.

### `lazy`

Options forwarded verbatim to `lazy.setup()`.

```lua
lazy = {
  change_detection = { notify = false },
  rocks = { hererocks = true },
  dev = { path = "~/git", fallback = true },
}
```

---

## lazy-workspaces.json

Tracks which workspaces are active. Created automatically at `stdpath("config")/lazy-workspaces.json` on first launch.

```json
{
  "user/repo": {
    "common": true,
    "personal": true,
    "work": false
  }
}
```

- Workspaces discovered on disk for the first time are **auto-included** (`true`)
- Excluded workspaces (`false`) are skipped — their specs and `setup()` are not loaded
- Stale entries (workspace removed from disk) emit a warning but are kept
- Can be managed via commands below. As well by hand.

---

## Commands

### `:LazyWorkspacesBootstrap [src] [out] [--dev]`

Migrates an existing config to lazy-workspaces format.

What it does:
- Detects workspaces under `lua/` (folders containing `init.lua`)
- Wraps `init.lua` content in `M.setup()`
- Moves any existing lazy bootstrap files (e.g. `lazy_init.lua`) to `*.bak`
- Detects subdirectories with `.lua` files and populates `specs` in the generated `init.lua`
- Generates a new root `init.lua` wired to `lazy-workspaces`

Defaults: `src = stdpath("config")`, `out = /tmp/nvim`.

`--dev` — generates `init.lua` using a local plugin path instead of GitHub clone. Useful when developing lazy-workspaces itself.

### `:LazyWorkspacesInclude <workspace>`

Marks a workspace as included in `lazy-workspaces.json`. Takes effect on next restart.

```vim
:LazyWorkspacesInclude work
:LazyWorkspacesInclude myconfig/common
```

Tab-completes currently excluded workspaces.

### `:LazyWorkspacesExclude <workspace>`

Marks a workspace as excluded. Takes effect on next restart.

```vim
:LazyWorkspacesExclude work
:LazyWorkspacesExclude myconfig/personal
```

Tab-completes currently included workspaces.

---

## How It Works

1. `init.lua` bootstraps lazy-workspaces from `stdpath("data")/lazy/` (clones if needed)
2. `setup()` resolves each config URL → local path (clones/pulls git repos as needed)
3. Workspaces are detected recursively under each config's `lua/` directory
4. `lazy-workspaces.json` is reconciled: new workspaces auto-included, excluded ones skipped, stale ones warned
5. Spec files from each active workspace's spec directories are collected and passed to `lazy.setup()`
6. After lazy startup, `M.setup()` is called for each active workspace

---

## Additional Customization

### Config path globals

After `setup()` resolves all configs, lazy-workspaces sets `vim.g.lw` with the local paths of every config:

```lua
vim.g.lw.configs       -- { config_name = local_path, ... }
vim.g.lw.config_paths  -- { local_path, ... }  (flat list)
```

These are available inside any workspace's `M.setup()` and plugin specs. Useful for pickers that span multiple config directories:

```lua
-- lua/personal/plugins/snacks.lua
keys = {
  { "<leader>fe", function()
      Snacks.picker.files({ dirs = vim.g.lw.config_paths })
  end, desc = "Find config file" },
}
```

For named access (e.g. when you have multiple configs and want a specific one):

```lua
vim.g.lw.configs["user/nvim.conf.d"]  -- → /home/user/.local/share/nvim/lazy-workspaces/nvim.conf.d
```

---

## Known Limitations

- **Symlinks not supported.** Bootstrap descends recursively — a symlink cycle will loop infinitely. Do not use symlinks inside `lua/`.
