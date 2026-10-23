# genja-finder.nvim

Two telescope pickers with a shared scope: live grep (rg/ack/grep, rerun per
keystroke) and live find (es/locate rerun per keystroke, else fd/rg --files with a fuzzy filter). Loaded from disk by the
config's `../../lua/lazyp/new/genja-finder.lua` (`dir =` spec, no trigger: it
loads on the first `require('genja-finder')` from `<F1>`, `<S-F1>`, `<leader>jj`
in `lua/genja/map-telescope.lua`). Read README.md and `doc/genja-finder.txt`.

How this file is kept: one heading per feature, one bullet per decision.
Unmarked bullets were stated by jaro. `(inferred)` marks Claude's reading of the
code or history: confirm or delete. `Hint:` is a working note for Claude.

## Layout

- `lua/genja-finder/init.lua`: `setup(opts)`, `live_grep()`, `live_find()`.
- `scope.lua`: shared roots, skip states, titles, layout, `<M-r>`/`<M-i>`/`<F1>`/`<M-c>`/`<M-C>`/`<C-p>`/`<M-f>` maps.
- `grep.lua`: one command builder per backend, `<M-g>` filters, status text.
- `find.lua`: file list command per backend.
- `refine.lua`: `<M-f>` filter, `<M-x>` exclude and `<BS>` undo for any picker (`filter`, `exclude`, `undo`, `toggle_exact`, `attach(map, { sorter?, exact_allowed? })`), `decorate(picker, attach?)`; holds the frozen search (`filtered`).
- `telemap.lua`: `Telemap(map)`, the shared picker keys (`<esc>`, `<F2>`/`<F3>`), moved here from the config's `lua/genja/fn/telemap.lua`.
- `init.lua` `attach_shared_keys(map)` = Telemap + refine keys; `enhance(picker)` = `decorate(picker, attach_shared_keys)`, for pickers elsewhere in the config.
- Option or key changes go into README.md and `doc/genja-finder.txt` too.

## Scope of the plugin

- Live grep and live find, plus reusable picker keys: `Telemap` and the refine decorator. Telescope extensions (finn, mycolors, mydirs, mylunsj, undersort) stay in the config.
- The plugin must not require `genja.*`; the config passes extra picker keys through the `attach(map)` option (Telemap).
- The decorator wraps any picker that passes its opts to `pickers.new`; pickers that don't call `attach_shared_keys(map)` in their own attach_mappings (the config's f2 pickers, ui-select, mylunsj do).
- Mappings stay in the config.

## Backends

- Live grep tries `rg`, `ack`, `grep`; each has its own builder. grep and ack can't read `.gitignore`, so there `gitignore+` acts like `vend+mods+dist`.
- Live find tries `es`, `locate`, `fd`, `fdfind`, `rg`, in its own list, separate from grep's.
- es (Everything) and locate are live find backends, not a separate picker: rerun per keystroke, min 2 chars, max 15000 results. locate is the Linux counterpart of es.
- es is skipped when Everything isn't running (`es -get-everything-version` fails), checked while the binary is picked; the next binary in the list is used.
- Non-ASCII output from es is not a concern.
- es/locate results keep hidden files and dotfiles (`path_filter` ignores `hidden`).
- Prompt for grep: `pattern  <backend flags>` (two spaces), starts after 2 characters.

## Root and skip states

- `<M-r>` cycles the root: `pwd` > `…/.git` > `bufdir` > `home`. Option values: `pwd`, `git`, `bufdir`, `home`.
- `<M-i>` cycles the skip state: `gitignore+` (default) > `vend+mods+dist` > `unrestricted`.
- `exclude` = node_modules, vendor, dist; `exclude_files` = `*.min.js`, `*.min.css`. The config spec adds `go/pkg/mod`.
- Hidden files: off in the config spec.
- `<M-g>` (grep only) cycles file filters: text, make, web, js, sys, shell, none. Written into the prompt in each backend's own flag syntax.

## Titles (exact wording)

- Grep prompt title: `recurseinteractive <bin> text-scan <dir>`. Spelling is jaro's; keep it.
- Find prompt title: `findz00r <bin> <dir>`.
- `<dir>` is the directory being scanned (follows `<M-r>` and an explicit `cwd`), always cut to its last three parts (`…/a/b/c`).
- Results title: `from:<root> <path> skip:<state>`, no space after the colons, `…/.git` with a Unicode ellipsis.
- A `cwd` passed by the caller (e.g. oil's directory) is root `arg`: title `from:arg`, first in the `<M-r>` cycle, kept through reopens and `<F1>`.
- The path follows `<M-r>`. It shortens to the last three components when longer than 80 characters or wider than the window.
- Paths in titles and the `<M-c>` popup are unix style on every OS: `c:/foo/bar`, forward slashes, lowercase drive letter, no trailing slash.

## Layout and keys

- Both use the ivy bottom pane, height `lines - 5` (min 35), list left, preview right (`mirror = false`).
- Preview is off by default; `<C-p>` toggles it. Find previews the file from the top.
- `<F1>` inside either picker switches to the other, keeping root, skip state and search text (grep -> find keeps only the pattern).
- `<M-c>` shows the running command in a centred popup; `y` copies it with no notification.
- `<M-C>` cycles through the command (binary) list of the current picker, reopening with the next one.
- Grep shows a status at the end of the prompt (`⟳ N …`, `N hits`).
- `<M-f>` freezes results and fuzzy-filters within them; `<M-F>` (find) filters by a file name part.
- `<M-x>` excludes the entries that contain any typed word (smartcase), from `finder.results` (static finders, or after `<M-f>`); a level like `<M-f>`, prefix `!word > `.
- `<BS>` on an empty prompt undoes the last `<M-f>` (finder, sorter, prefix, title and text kept per step in `refine.lua`).
- `<M-n>` switches fuzzy/exact (telescope's substring matcher). New `<M-f>` steps start in the current mode; undo restores the step's mode. Live grep: only after `<M-f>`.
- Toggles read the prompt text from the prompt buffer at keypress, so the latest input carries over.

## Code style

- No `x and y or z` to build values; plain assignments and `if` blocks. About a dozen older ones remain in `grep.lua`/`scope.lua`; ask before rewriting them. (inferred: question left open)
