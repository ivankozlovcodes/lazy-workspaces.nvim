# lazy-workspaces.nvim

Split your Neovim config into modular **workspaces** — each with its own options, keymaps, and plugins — loaded automatically by [lazy.nvim](https://github.com/folke/lazy.nvim).

Useful when you maintain one config repo shared across contexts (personal, work, machine-specific) and want to enable only the relevant parts per environment.

## Getting Started

### Main path — existing Neovim config

**1.** Add `lazy-workspaces` to your lazy.nvim spec:

```lua
{
  "ivankozlovcodes/lazy-workspaces.nvim",
  lazy = false,
  priority = 1000,
  opts = { workspaces = {} },
}
```

**2.** Open Neovim. Run the migrate command, pointing at your current config and an output directory:

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

Scaffold a minimal working skeleton:

```bash
bash <(curl -s https://raw.githubusercontent.com/ivankozlovcodes/lazy-workspaces.nvim/main/scripts/new-config.sh)
```

Then open the scaffolded config:

```bash
nvim -u /tmp/lazy-workspaces.conf.d/init.lua
```

`lazy-workspaces` is loaded — run `:LazyWorkspacesBootstrap` from there to migrate any existing workspace repo into the right structure.

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

```lua
opts = {
  workspaces = {
    {
      url    = "file://~/git/nvim.conf.d",  -- repo containing your lua/ workspaces
      branch = "main",                       -- optional, git only
      enable = { "common", "personal" },    -- workspace names to load
    },
    {
      url    = "git@github.com:user/work-nvim.git",
      branch = "stable",
      enable = { "work" },
    },
  },
}
```

**URL schemes supported:**

| Scheme | Behavior |
|---|---|
| `file://~/path` | Load from local directory |
| `https://` / `git@` | Clone on first start; async pull on subsequent starts |

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
- Generates a new root `init.lua` wired to `lazy-workspaces`

## How It Works

1. `lazy-workspaces` loads with `lazy = false` during Neovim startup
2. For each workspace source, resolves the URL to a local path and adds it to `runtimepath`
3. Calls `require("<workspace>").setup()` for each enabled workspace (options, keymaps, autocmds)
4. Scans `<workspace>/plugins/*.lua`, loads each spec file, and injects them into the live lazy.nvim registry

Plugin injection happens after lazy's spec-processing phase using lazy's internal APIs — no separate `{ import = "..." }` entries needed in your `init.lua`. Workspace specs are also patched into `Config.options.spec` so `:Lazy sync` and `:Lazy clean` include them correctly.

## Roadmap

- [ ] `:WorkspaceEnable` / `:WorkspaceDisable` / `:WorkspaceRefresh` commands
- [ ] `:Install <workspace> <author/plugin>` — generate plugin spec file in workspace
- [x] Auto-install newly injected plugins without manual `:Lazy install`
