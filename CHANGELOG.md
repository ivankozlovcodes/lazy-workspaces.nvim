## [0.2.0] - 2026-05-20

### 🚀 Features

- [**breaking**] Recognize neighbor spec dirs at any container depth
Previously spec dirs (e.g. plugins/) were only recognized when placed
directly under lua/. Dirs with the same name inside container dirs
were silently treated as workspaces instead.

Now classify_dirs checks spec_dir_set at every nesting level and
bubbles discovered specs up through container boundaries.

```
  Before:
    -- opts: specs = { "plugins" }
    -- lua/
    --   group/
    --     default/   → workspace ✓
    --     plugins/   → workspace ✓  (bug: should be spec dir)

  After:
    -- opts: specs = { "plugins" }
    -- lua/
    --   group/
    --     default/   → workspace ✓
    --     plugins/   → spec dir ✓   (files loaded as lazy specs)
```


## [0.1.3] - 2026-05-20

### 🚀 Features

- Add workspace sync command
  - `:LazyWorkspacesSync` command will attempt to pull all knowing
    workspaces
  - refactor: move common operation into helper functions so I don't go
    crazy
  - refactor: move opts related operations to opts.lua;
  - test: add opts_spec


- Auto pull configs on nvim start

- Add autocomplete for opts.lazy as LazyConfig

## [0.1.2] - 2026-05-19

### 🚀 Features

- Load configs in order they introduced in opts.configs
- Recognize folders at lua/ root as plugin specs if in opts.specs

### 🚜 Refactor

- Split workspace detection into scan_dir + classify_dirs

### 🎨 Styling

- Add stylua.toml for fix ::label:: parse errors;

### 🧪 Testing

- Refactor init_spec into several fixtures
- Add tests for outside of workspace spec folder deteciton logic

## [0.1.1] - 2026-05-19

### 🚀 Features

- Support direct opts.spec injection for lazy

## [0.1.0] - 2025-05-17

- Johnny must revert to this version if breaks

