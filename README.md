# lazy-workspaces.nvim

Split your Neovim config into modular **workspaces** — each with its own options, keymaps, and plugins — loaded automatically by [lazy.nvim](https://github.com/folke/lazy.nvim).

Useful when you maintain one config repo shared across contexts (personal, work, machine-specific) and want to enable only the relevant parts per environment.

## Requirements

- Neovim 0.10+
- [lazy.nvim](https://github.com/folke/lazy.nvim)

---

## Getting Started

### Option A — Add to existing config

Add `lazy-workspaces` to your lazy.nvim spec:

```lua
{ "ivankozlovcodes/lazy-workspaces.nvim", lazy = false, opts = {} }
```

Open Neovim — lazy installs the plugin. Then migrate your config:

```vim
:LazyWorkspacesBootstrap
```

See [Bootstrap](#bootstrap) for what this does. Test the result:

```bash
nvim -u /tmp/nvim/init.lua
```

Happy? Move it into place:

```bash
mv /tmp/nvim ~/.config/nvim
```

> **Warning:** This overwrites `~/.config/nvim` and cannot be undone. Back up first — or better yet, manage your config with git. lazy-workspaces [supports git URLs](#configuration), so your workspaces can live in a repo and be pulled automatically on every start.

---

### Option B — Lazy to type?

Run the setup script:

```bash
curl -s https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/main/scripts/new-config.sh | bash
```

Open it:

```bash
nvim -u /tmp/nvim/init.lua
```

Migrate your config:

```vim
:LazyWorkspacesBootstrap
```

Test and move into place as in Option A.

---

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

---

## Configuration

`collect()` resolves each workspace source, scans `plugins/*.lua` files, and returns a flat list of lazy.nvim specs.

```lua
workspace_specs = require("lazy-workspaces").collect({
  workspaces = {
    {
      url    = "git@github.com:ivankozlovcodes/nvim.conf.d.git",
      enable = { "common", "personal" },
    },
  },
})
```

**URL schemes:**

| Scheme | Behavior |
|---|---|
| `file://~/path` | Load from local directory |
| `https://` / `git@` | Clone on first start; pull on subsequent starts |

**Offline / first-run fallback:** if the lazy-workspaces clone fails (no internet), `workspace_specs` stays empty and lazy installs it on the next run.

Full `init.lua` example:

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
      -- TODO: replace with real setup example
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

---

## Bootstrap

What `:LazyWorkspacesBootstrap` does to your config:

- Detects workspaces (each `lua/<name>/` folder with `init.lua`)
- Renames `lazy/` → `plugins/` inside each workspace
- Wraps `init.lua` body in `M.setup()`
- Moves any existing lazy bootstrap file (e.g. `lazy_init.lua`) to `*.bak`
- Generates a new root `init.lua` wired to `lazy-workspaces`

---

## How It Works

1. `init.lua` bootstraps lazy-workspaces from `stdpath("data")/lazy/` (cloning if needed)
2. `collect()` resolves workspace sources, adds them to `runtimepath`, and scans each `plugins/` directory for lazy.nvim specs
3. The returned spec list is passed directly to `lazy.setup()` — lazy handles installation, updates, and key/event/command triggers natively
4. After lazy's startup completes, `M.setup()` is called for each workspace (options, keymaps, autocmds)

---

## Roadmap

- [ ] `:WorkspaceEnable` / `:WorkspaceDisable` / `:WorkspaceRefresh` commands
- [ ] `:Install <workspace> <author/plugin>` — generate plugin spec file in workspace
- [x] Auto-install newly injected plugins without manual `:Lazy install`
