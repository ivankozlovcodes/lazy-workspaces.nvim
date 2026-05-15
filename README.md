# lazy-workspaces.nvim

Split your Neovim config into modular **workspaces** — each with its own options, keymaps, and plugins — loaded automatically by [lazy.nvim](https://github.com/folke/lazy.nvim).

Useful when you maintain one config repo shared across contexts (personal, work, machine-specific) and want to enable only the relevant parts per environment.

## Getting Started

### Main path — existing Neovim config

**1.** Scaffold a minimal config with `lazy-workspaces` already wired up:

```bash
bash <(curl -s https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/main/scripts/new-config.sh)
```

**2.** Open the scaffolded config and run the migrate command, pointing at your existing config:

```bash
nvim -u /tmp/lazy-workspaces.conf.d/init.lua
```

```vim
:LazyWorkspacesBootstrap ~/.config/nvim /tmp/migrated-nvim
```

This converts your existing config into workspace format (see [Bootstrap](#bootstrap) for details).

**3.** Test the result without touching your real config:

```bash
nvim -u /tmp/migrated-nvim/init.lua
```

**4.** Happy with the result? Replace your config with the output directory.

---

### Side path — no Neovim config yet

The scaffold from step 1 above is already a working base. Add your workspaces to the `collect()` call in `init.lua` and start building.

---

## Requirements

- Neovim 0.10+
- [lazy.nvim](https://github.com/folke/lazy.nvim)

## Workspace Structure

Each workspace is a folder under `lua/` with an `init.lua` exposing `M.setup()` and a `plugins/` directory with lazy.nvim specs:

```
nvim.conf.d/
  lua/
    common/
      init.lua        -- M.setup(): options, keymaps, autocmds
      plugins/
        treesitter.lua
        blink.lua
        ...
    personal/
      init.lua
      plugins/
        lazygit.lua
        ...
    work/
      init.lua
      plugins/
```

`init.lua` example:

```lua
local M = {}

function M.setup()
  vim.opt.number = true
  vim.keymap.set("n", "<leader>q", "<cmd>q<cr>")
  -- etc.
end

return M
```

Plugin spec files follow standard lazy.nvim format:

```lua
-- lua/common/plugins/treesitter.lua
return {
  "nvim-treesitter/nvim-treesitter",
  build = ":TSUpdate",
  opts = {},
}
```

## Configuration

`init.lua` bootstraps both lazy.nvim and lazy-workspaces, then calls `collect()` to build the plugin spec before passing it to `lazy.setup()`:

```lua
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
    workspaces = {
      {
        url    = "file://~/git/nvim.conf.d",
        enable = { "common", "personal" },
      },
      {
        url    = "git@github.com:user/work-nvim.git",
        branch = "stable",
        enable = { "work" },
      },
    },
  })
end

require("lazy").setup({
  spec = vim.list_extend(workspace_specs, {
    { "ivankozlovcodes/lazy-workspaces.nvim", lazy = false, opts = {} },
  }),
  change_detection = { notify = false },
})
```

`collect()` resolves each workspace source, scans `plugins/*.lua` files, and returns a flat list of lazy.nvim specs. Workspace `M.setup()` calls (options, keymaps, autocmds) are scheduled to run after lazy's startup completes.

**URL schemes supported:**

| Scheme | Behavior |
|---|---|
| `file://~/path` | Load from local directory |
| `https://` / `git@` | Clone on first start; pull on subsequent starts |

**Offline / first-run fallback:** if the lazy-workspaces clone fails (no internet), `workspace_specs` stays empty and lazy installs it on the next run when the network is available.

## Bootstrap

Already have a Neovim config and want to migrate it? Use the built-in bootstrap command:

```vim
:LazyWorkspacesBootstrap [src_dir] [out_dir]
```

- `src_dir` — config to migrate (default: `stdpath("config")`)
- `out_dir` — where to write the result (default: `/tmp/lazy-workspaces.conf.d`)

**Example:**

```vim
:LazyWorkspacesBootstrap ~/.config/nvim /tmp/migrated-nvim
```

Test the result without touching your real config:

```bash
nvim -u /tmp/migrated-nvim/init.lua
```

**What bootstrap does:**

- Detects workspaces (each `lua/<name>/` folder with `init.lua`)
- Renames `lazy/` → `plugins/` inside each workspace
- Wraps `init.lua` body in `M.setup()`
- Moves any existing lazy bootstrap file (e.g. `lazy_init.lua`) to `*.bak`
- Generates a new root `init.lua` wired to `lazy-workspaces`

## How It Works

1. `init.lua` bootstraps lazy-workspaces from `stdpath("data")/lazy/` (cloning if needed)
2. `collect()` resolves workspace sources, adds them to `runtimepath`, and scans each `plugins/` directory for lazy.nvim specs
3. The returned spec list is passed directly to `lazy.setup()` — lazy handles installation, updates, and key/event/command triggers natively
4. After lazy's startup completes, `M.setup()` is called for each workspace (options, keymaps, autocmds)

## Roadmap

- [ ] `:WorkspaceEnable` / `:WorkspaceDisable` / `:WorkspaceRefresh` commands
- [ ] `:Install <workspace> <author/plugin>` — generate plugin spec file in workspace
- [x] Auto-install newly injected plugins without manual `:Lazy install`
