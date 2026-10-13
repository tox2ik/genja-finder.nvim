# genja-finder.nvim

Two telescope pickers with a shared scope:

- **live grep** (`require('genja-finder').live_grep()`): text search with rg, ack or GNU grep,
  rerun on each keystroke. Prompt: `pattern  -g *.lua` (two spaces, then backend flags).
- **live find** (`require('genja-finder').live_find()`): fuzzy match over the file list from
  `fd` or `rg --files`.

In both pickers:

| key | does |
|---|---|
| `<M-r>` | cycle where the scan starts: pwd > …/.git > bufdir > home |
| `<M-i>` | cycle what is skipped: gitignore+ > vend+mods+dist > unrestricted |
| `<F1>` | switch between live grep and live find, keeping root, skip and search text |
| `<M-c>` | popup with the command being run; `y` copies it |
| `<C-p>` | toggle the preview (off by default) |
| `<M-g>` | live grep only: cycle a file filter (text, make, web, js, sys, shell, none) |

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
		find = { follow = false },
	},
	config = function(_, opts) require('genja-finder').setup(opts) end,
}
```

No keys are mapped globally; map `live_grep` / `live_find` yourself. All options and
types are in `lua/genja-finder/scope.lua` (`genja-finder.ScanOpts`), `grep.lua`
(`genja-finder.GrepOpts`) and `find.lua` (`genja-finder.FindOpts`). See `:help genja-finder`.
