# genja-finder.nvim

Two telescope pickers with a shared scope:

- **live grep** (`require('genja-finder').live_grep()`): text search with rg, ack or GNU grep,
  rerun on each keystroke. Prompt: `pattern  -g *.lua` (two spaces, then backend flags).
- **live find** (`require('genja-finder').live_find()`): files by name. With `es` (Everything,
  Windows, only while Everything runs) or `locate` (Linux) the index is queried on each keystroke
  (2+ characters, at most 15000 paths; es takes Everything's search syntax). Otherwise fuzzy match
  over the file list from `fd` or `rg --files`.

In both pickers:

| key | does |
|---|---|
| `<M-r>` | cycle where the scan starts: pwd > …/.git > bufdir > home; a `cwd` passed to the picker is `arg`, first in the cycle |
| `<M-i>` | cycle what is skipped: gitignore+ > vend+mods+dist > unrestricted |
| `<F1>` | switch between live grep and live find, keeping root (and an explicit `cwd`), skip and search text |
| `<M-c>` | popup with the command being run; `y` copies it |
| `<M-C>` | reopen with the next command in the binary list (skips missing or not ready ones) |
| `<C-p>` | toggle the preview (off by default) |
| `<M-f>` | filter: freeze the listed results and fuzzy-match within them; again narrows further |
| `<M-F>` | live find only: popup for a file name part (`.ahk`); lists only files whose name contains it |
| `<M-g>` | live grep only: cycle a file filter (text, make, web, js, sys, shell, none) |

For any other telescope picker:

| call | does |
|---|---|
| `require('genja-finder').attach_shared_keys(map)` | in a picker's `attach_mappings`: Telemap keys (`<esc>`, `<F2>`/`<F3>`) and `<M-f>` filter |
| `require('genja-finder').enhance(picker)` | wraps a picker function with those keys, e.g. `enhance(require('telescope.builtin').oldfiles)` |
| `require('genja-finder.refine').decorate(picker, attach?)` | the same with your own keys (default: `<M-f>` only) |
| `require('genja-finder.telemap').Telemap(map)` | Telemap keys only |

`enhance` and `decorate` set `opts.attach_mappings`; telescope runs it after the picker's own. A picker
that doesn't pass its opts to `pickers.new` gets nothing; call `attach_shared_keys(map)` inside it.

## Setup (lazy.nvim)

```lua
{
	dir = vim.fn.stdpath('config') .. '/plug-wip/genja-finder.nvim',
	dependencies = { 'nvim-telescope/telescope.nvim' },
	opts = {
		exclude = { 'node_modules', 'vendor', 'dist' },
		exclude_files = { '*.min.js', '*.min.css' },
		attach = function(map) --[[ extra picker keys ]] end,
		grep = { min_chars = 2 },
		find = { follow = false, min_chars = 2, max_results = 15000 },
	},
	config = function(_, opts) require('genja-finder').setup(opts) end,
}
```

Both pickers heed telescope's global `file_ignore_patterns` (Lua patterns matched anywhere
in the path), in every skip mode including unrestricted; the `<M-c>` command doesn't show
them. Anchor extension patterns (`"%.a$"`, not `"%.a"`, which also hides `*.ahk`), or
override for the finder with `file_ignore_patterns = {}` in `opts` (`<F1>` keeps it).

No keys are mapped globally; map `live_grep` / `live_find` yourself. All options and
types are in `lua/genja-finder/scope.lua` (`genja-finder.ScanOpts`), `grep.lua`
(`genja-finder.GrepOpts`) and `find.lua` (`genja-finder.FindOpts`). See `:help genja-finder`.
