---@diagnostic disable: undefined-field

-- genja-finder.scope: shared scope togglers for live grep (genja-finder.grep) and live find (genja-finder.find):
-- where the scan starts (<M-r>), what it skips (<M-i>), and the titles that show both.
--
--         <M-r> cycle root (pwd > …/.git > bufdir > home), shown as `from:<root>`; a `cwd` passed
--               by the caller is root `arg`, first in the cycle,
--         <M-Up> one-off: rescan in the parent of the scanned dir; root and the <M-r> cycle stay
--         <M-i> cycle what is excluded from the scan (gitignore+ > vend+mods+dist > unrestricted):
--               gitignore+     (default) skips what .gitignore/.ignore list, plus node_modules, vendor and dist
--                              and *.min.js / *.min.css files (`exclude`, `exclude_files`).
--               vend+mods+dist skips only those dirs and *.min.js / *.min.css; paths in .gitignore are searched.
--               unrestricted   skips nothing (--no-ignore), vendor/, node_modules/ and dist/ are searched too.
--               .git is excluded in all modes. Backends that can't read .gitignore (grep, ack)
--               treat gitignore+ as vend+mods+dist.
--         <F1>  switch between live grep and live find, keeping root, skip and the search text.
--         <M-c> popup with the command being run; `y` copies it to the clipboard, <M-c> closes it.
--         <M-C> reopen with the next command in `binary` (rg > ack > grep, es > locate > fd > …),
--               skipping ones not in PATH or not ready; wraps around.
--         <C-p> toggle the preview (off by default; replaces telescope's <C-p> = previous item).
--         <M-f> filter: freeze the listed results and fuzzy-match within them on a fresh prompt;
--               press again to narrow further. The search moves into the prompt prefix (`foo > `).
--               <M-r>, <M-i>, <F1> and <M-c> still act on that search, not on the filter text.
--         <BS>  on an empty prompt: undo the last <M-f>.
--         <M-n> switch between fuzzy and exact match (grep: after <M-f> only).

---@alias genja-finder.ScanRoot 'pwd'|'git'|'bufdir'|'home'|'arg'
---@alias genja-finder.ScanIgnore 'gitignore+'|'vend+mods+dist'|'unrestricted'

---The `map` that telescope passes to attach_mappings(prompt_bufnr, map).
---@alias genja-finder.TelescopeMap fun(mode: 'i'|'n'|('i'|'n')[], lhs: string, action: string|table|fun(prompt_bufnr: integer)|false, opts?: vim.keymap.set.Opts)
-- action false: the key counts as mapped and telescope skips its default for it

---Options shared by the live pickers.
---@class genja-finder.ScanOpts
---@field binary? string|string[]  binaries tried in PATH, first found wins
---@field backend? string          builder to use, if the binary name isn't a known one
---@field bin? string              binary in use, name without extension (set internally, for <M-C>)
---@field root? genja-finder.ScanRoot     where the scan starts (default 'pwd')
---@field cwd? string|false        explicit directory: scanned as root 'arg', kept in the <M-r> cycle
---@field arg_dir? string          the caller's cwd, for root 'arg' (set internally, kept on reopen)
---@field one_off? boolean         cwd came from <M-Up>: don't turn it into root 'arg' (set internally, <M-r> clears it)
---@field hidden? boolean          include dotfiles (default true)
---@field ignore? genja-finder.ScanIgnore what is excluded from the scan (default 'gitignore+')
---@field exclude? string[]        names excluded in 'gitignore+' and 'vend+mods+dist' (default node_modules, vendor, dist)
---@field exclude_files? string[]  file globs excluded in the same states (default *.min.js, *.min.css)
---@field file_ignore_patterns? string[] telescope's own filter: Lua patterns matched anywhere in the path, applied
---                                after the backend in every skip mode (also unrestricted; not shown by <M-c>).
---                                Unset: telescope's global file_ignore_patterns. {} turns it off.
---@field default_text? string     initial prompt
---@field ivy? boolean             ivy bottom pane layout, the old finn look (default true)
---@field show_preview? boolean    show the preview when the picker opens (default false, <C-p> toggles)
---@field attach? fun(map: genja-finder.TelescopeMap) extra picker keys, e.g. your own shared mappings
---@field origin_win? integer      window the picker was opened from (set internally, kept on reopen)
---@field origin_pwd? string       :pwd when the picker was first opened (set internally, kept on reopen)
---@field separator? string        grep only: between the pattern and the backend flags in the prompt

local SRC = 'genja-finder/scope.lua: '

local float = require('genja-util.float')

local M = {}

---@type genja-finder.ScanOpts
M.defaults = {
	root = 'pwd',
	hidden = true,
	ignore = 'gitignore+',
	exclude = { 'node_modules', 'vendor', 'dist', '**/go/pkg/mod' }, -- the pattern works only for fd
	exclude_files = { '*.min.js', '*.min.css' },
	ivy = true,
	show_preview = false, -- not `preview`: that key is telescope's own preview config
}

---@type genja-finder.ScanRoot[]
M.roots = {
	'pwd', -- Neovim's working directory (:pwd), same as builtin live_grep. Scans everything below it.
	'git', -- shown as `…/.git`: nearest parent of the current file (or of pwd) holding .git,
	-- scans the whole repo even when :pwd is a subfolder. Falls back to pwd outside a repo.
	'bufdir', -- folder of the current buffer's file: narrowest scan, that folder and below only.
	-- Falls back to pwd for non-file buffers (help, oil, terminal).
	'home', -- user home dir ($HOME): widest scan, slow without a filter or the gitignore+ skip.
}

---Title text per root, where it differs from the name.
---@type table<genja-finder.ScanRoot, string>
M.root_labels = { git = '…/.git' }

---@type genja-finder.ScanIgnore[]
M.ignores = {
	'gitignore+',  -- .gitignore/.ignore rules + `exclude` (node_modules, vendor, dist)
	'vend+mods+dist', -- only `exclude`; .gitignore'd paths are searched (--no-ignore)
	'unrestricted', -- nothing excluded but .git (--no-ignore)
}

---Next item after `v` in `list`, wrapping around.
---@generic T
---@param list T[]
---@param v T
---@return T
function M.cycle(list, v)
	for i, x in ipairs(list) do
		if x == v then return list[i % #list + 1] end
	end
	return list[1]
end

---@param bins string|string[]
---@return string[]
local function as_list(bins)
	return (type(bins) == 'string' and { bins } or bins)
end

---First binary of `bins` found in PATH (and accepted by `usable`, when given).
---@param bins string|string[]
---@param usable? fun(exe: string, name: string): boolean false skips to the next binary
---@return string? exe full path
---@return string? name binary without dir and extension
function M.find_binary(bins, usable)
	for _, b in ipairs(as_list(bins)) do
		local exe = vim.fn.exepath(b)
		if exe ~= '' then
			local name = vim.fn.fnamemodify(b, ':t:r')
			if not usable or usable(exe, name) then return exe, name end
		end
	end
end

---`bins` reordered to start after `name`, so find_binary tries the next one first (<M-C>).
---Missing or not ready binaries are skipped by find_binary as usual.
---@param bins string|string[]
---@param name? string binary in use, without dir and extension
---@return string[]
function M.after(bins, name)
	local list = as_list(bins)
	local at = 0
	for i, b in ipairs(list) do
		if vim.fn.fnamemodify(b, ':t:r') == name then at = i end
	end
	local out = {}
	for k = 1, #list do
		out[k] = list[(at + k - 1) % #list + 1]
	end
	return out
end

---Scan dir for `root`, seen from window `win` (its :pwd and its buffer).
---@param root genja-finder.ScanRoot
---@param win integer
---@param arg_dir? string the dir for root 'arg' (falls back to pwd without one)
---@return string dir
function M.resolve_root(root, win, arg_dir)
	local cwd = vim.fn.getcwd(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local name = vim.api.nvim_buf_get_name(buf)
	local is_file = name ~= '' and vim.bo[buf].buftype == ''
	if root == 'arg' and arg_dir then
		return arg_dir
	elseif root == 'bufdir' then
		return is_file and vim.fs.dirname(name) or cwd
	elseif root == 'git' then
		return vim.fs.root(is_file and name or cwd, '.git') or cwd
	elseif root == 'home' then
		return vim.env.HOME or vim.uv.os_homedir() or cwd
	end
	return cwd
end

---Path for titles and popups, unix style on every OS: forward slashes, no trailing
---slash, lowercase drive letter (`c:/foo/bar`).
---@param path string
---@return string
function M.display_path(path)
	local shown = vim.fs.normalize(path):gsub('([^:])/$', '%1') -- keeps 'c:/' and '/'
	shown = shown:gsub('^(%a):', function(drive) return drive:lower() .. ':' end)
	return shown
end

---Full path, or `…/a/b/c` (last three components) when longer than 80 chars
---or wider than the current window (minus `reserved` columns). Unix style (display_path).
---@param path string
---@param reserved? integer columns already used by the rest of the title
---@return string
function M.short_path(path, reserved)
	local shown = M.display_path(path)
	local room = vim.api.nvim_win_get_width(0) - (reserved or 0)
	if #shown <= 80 and vim.fn.strdisplaywidth(shown) <= room then
		return shown
	end
	return M.tail_path(shown)
end

---Last three components of `path`, with `…` in front when some were cut. Unix style (display_path).
---@param path string
---@return string
function M.tail_path(path)
	local shown = M.display_path(path)
	local parts = vim.split(shown, '/', { plain = true, trimempty = true })
	if #parts <= 3 then return shown end
	return '…/' .. table.concat(parts, '/', #parts - 2)
end

---Layout for pickers.new defaults: ivy bottom pane, screen height minus 5 lines (min 35),
---file list left, preview right.
---@param o genja-finder.ScanOpts
---@return table
function M.look(o)
	if not o.ivy then return {} end
	return vim.tbl_deep_extend('force', require('telescope.themes').get_ivy(), {
		layout_config = {
			height = function(_, _, max_lines) return math.max(max_lines - 5, 35) end,
			preview_width = 0.4,
			mirror = false, -- global `mirror = true` would put the preview left; keep the list left
		},
	})
end

---Open `picker`, with its previewer parked unless `o.show_preview`.
---Telescope only reads preview.hide_on_startup from the global config, so hide it the way
---actions.layout.toggle_preview does: move it to `hidden_previewer`, <C-p> brings it back.
---@param picker table from pickers.new
---@param o genja-finder.ScanOpts
function M.find(picker, o)
	if not o.show_preview and picker.previewer then
		picker.hidden_previewer = picker.previewer
		picker.previewer = nil
	end
	picker:find()
end

---Search text the results of the picker in `bufnr` were frozen with (<M-f>), nil when not filtered.
---@param bufnr integer prompt buffer
---@return string?
function M.filtered(bufnr) return require('genja-finder.refine').filtered(bufnr) end

---Current search text of the picker in `bufnr`, read from that prompt buffer itself
---(not from whatever buffer is current), without the prompt prefix.
---While filtered (<M-f>) it is the search the results were frozen with, not the filter text.
---@param bufnr integer prompt buffer, as passed to the mapping
---@return string
function M.prompt(bufnr)
	local refine = require('genja-finder.refine')
	return refine.filtered(bufnr) or refine.text(bufnr)
end

---Same directory, ignoring slash style, a trailing slash and (on Windows) case.
---@param a string
---@param b string
---@return boolean
local function same_dir(a, b)
	a = vim.fs.normalize(a):gsub('/$', '')
	b = vim.fs.normalize(b):gsub('/$', '')
	if vim.fn.has('win32') == 1 then
		return a:lower() == b:lower()
	end
	return a == b
end

---Pin the origin window and resolve `o.cwd` from `o.root`. Call before building the picker.
---A caller's `cwd` becomes root 'arg' (dir kept in o.arg_dir, part of the <M-r> cycle).
---@param o genja-finder.ScanOpts
function M.prepare(o)
	-- resolve roots against the window we came from, not whatever is current during a reopen
	if not (o.origin_win and vim.api.nvim_win_is_valid(o.origin_win)) then
		o.origin_win = vim.api.nvim_get_current_win()
	end
	o.origin_pwd = o.origin_pwd or vim.fn.getcwd(o.origin_win)

	-- first open with a cwd from the caller; reopens carry arg_dir already, and their cwd is
	-- the resolved root's dir, so it only counts when it differs from that
	local from_caller = o.arg_dir == nil and o.cwd and o.root ~= 'arg' and not o.one_off
	if from_caller and not same_dir(o.cwd, M.resolve_root(o.root, o.origin_win)) then
		o.arg_dir = o.cwd
		o.root = 'arg'
	end
	o.cwd = o.cwd or M.resolve_root(o.root, o.origin_win, o.arg_dir)
end

---Split a grep prompt at `sep`: the pattern, and the backend args after it (nil without `sep`).
---@param prompt string
---@param sep string
---@return string pattern
---@return string|nil rest
function M.split_prompt(prompt, sep)
	local at = prompt:find(sep, 1, true)
	if not at then
		return prompt, nil
	end
	return prompt:sub(1, at - 1), prompt:sub(at + #sep)
end

---Roots <M-r> cycles through: 'arg' first when the caller passed a dir.
---@param o genja-finder.ScanOpts
---@return genja-finder.ScanRoot[]
function M.root_cycle(o)
	if not o.arg_dir then
		return M.roots
	end
	return vim.list_extend({ 'arg' }, M.roots)
end

---Prompt title `<label> <last 3 parts of the scan dir>` and results title `from:<root> <path> skip:<ignore>`.
---@param o genja-finder.ScanOpts
---@param label string e.g. 'recurseinteractive rg text-scan'
---@return string prompt_title
---@return string results_title
function M.titles(o, label)
	label = label .. ' '
	local from = 'from:' .. (M.root_labels[o.root] or o.root) .. ' '
	local skip = ' skip:' .. o.ignore
	return label .. M.tail_path(o.cwd),
		from .. M.short_path(o.cwd, vim.fn.strdisplaywidth(from .. skip)) .. skip
end

---The other live picker, for <F1> switching
---@type table<string, fun(): fun(opts: genja-finder.ScanOpts)>
M.switch = {
	grep = function() return require('genja-finder.grep').live_grep end,
	find = function() return require('genja-finder.find').live_find end,
}

---Command as one copyable line; args with spaces or shell characters get double quotes.
---@param cmd string[]
---@return string
function M.cmdline(cmd)
	return table.concat(vim.tbl_map(function(a)
		if a == '' or a:find '[%s"\'!*?<>|&;$`^%%()]' then return '"' .. a:gsub('"', '\\"') .. '"' end
		return a
	end, cmd), ' ')
end

---Command popups, by prompt buffer.
---@type table<integer, { win: integer, buf: integer }>
local popups = {}

---Close the command popup of prompt buffer `bufnr` and drop its temporary `y` mapping.
---@param bufnr integer
local function close_command(bufnr)
	local p = popups[bufnr]
	if not p then return end
	popups[bufnr] = nil
	float.close(p.win)
	if vim.api.nvim_buf_is_valid(bufnr) then
		pcall(vim.keymap.del, { 'i', 'n' }, 'y', { buffer = bufnr })
	end
end

---Toggle a popup in the middle of the screen with the command being run. It does not take
---focus (leaving the prompt would close telescope); while it is open, `y` in the prompt
---copies the command to the clipboard (+) and closes the popup, <M-c> closes it.
---@param bufnr integer prompt buffer
---@param cmd string[]? nil: nothing running yet
---@param cwd string directory the command runs in
function M.show_command(bufnr, cmd, cwd)
	if popups[bufnr] then return close_command(bufnr) end
	local line = cmd and M.cmdline(cmd) or '(nothing running yet: the pattern is too short)'
	local width = math.min(vim.o.columns - 6, math.max(60, vim.fn.strdisplaywidth(line), #cwd + 4))
	local lines = { line, '', 'in: ' .. M.display_path(cwd), '', cmd and 'y: copy to clipboard    <M-c>: close' or '<M-c>: close' }
	local height = 0
	for _, l in ipairs(lines) do height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width)) end

	local buf = float.scratch(lines)
	local win = float.open(buf, { width = width, height = height, title = 'command', enter = false, zindex = 200, up = 1 })
	vim.wo[win].wrap = true
	popups[bufnr] = { win = win, buf = buf }

	if cmd then
		vim.keymap.set({ 'i', 'n' }, 'y', function()
			vim.fn.setreg('+', line)
			close_command(bufnr)
		end, { buffer = bufnr, nowait = true, desc = 'scan: copy command (rg/ack/fd/find)' })
	end
	-- picker closed (<Esc>, <CR>, ...) while the popup is up
	vim.api.nvim_create_autocmd({ 'BufLeave', 'BufWipeout' }, {
		buffer = bufnr, once = true, callback = function() close_command(bufnr) end,
	})
end

---One-line input popup in the middle of the screen, opened in insert mode with `default`.
---<CR> calls `done(text)`, <Esc> (or leaving the popup) calls `done(nil)`. Open it after the
---picker is closed: it takes focus.
---@param title string
---@param default string
---@param done fun(text: string?)
function M.ask(title, default, done)
	local buf = float.scratch({ default })
	local win = float.open(buf, { width = math.min(vim.o.columns - 6, 50), height = 1, title = title, zindex = 200, up = 1 })
	local answered = false
	local function finish(text)
		if answered then return end
		answered = true
		float.close(win)
		vim.schedule(function() done(text) end)
	end
	vim.keymap.set({ 'i', 'n' }, '<CR>', function()
		finish(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or '')
	end, { buffer = buf })
	vim.keymap.set({ 'i', 'n' }, '<Esc>', function() finish(nil) end, { buffer = buf })
	vim.api.nvim_create_autocmd('WinLeave', { buffer = buf, once = true, callback = function() finish(nil) end })
	vim.cmd.startinsert { bang = true }
end

---Call `o.attach(map)` first (user keys), then map the togglers below.
---Map <M-c>: command popup (see show_command), when `command` is given.
---Map <M-r>, <M-i> and <M-C>: each closes the picker and reopens it via `open` with the changed
---option (root, skip, next binary), keeping the prompt text.
---Map <M-f>: refine to a filter over the listed results, <BS> on an empty prompt undoes it, <M-n> exact match
---(genja-finder.refine; see M.prompt, M.filtered).
---Map <F1>: close and open the other picker (`other`: 'grep' or 'find') with the same
---root, skip, file_ignore_patterns, origin window and search text (grep's extra args after the separator are dropped).
---@param map genja-finder.TelescopeMap
---@param o genja-finder.ScanOpts
---@param open fun(opts: genja-finder.ScanOpts) the picker function itself (live_grep, live_find)
---@param other? 'grep'|'find' picker <F1> switches to
---@param command? fun(prompt: string): string[]? command line for the current prompt
function M.map(map, o, open, other, command)
	local actions = require 'telescope.actions'
	if o.attach then o.attach(map) end

	local function reopen(bufnr, patch)
		local prompt = M.prompt(bufnr)
		actions.close(bufnr)
		vim.schedule(function()
			open(vim.tbl_extend('force', o, patch, { default_text = prompt }))
		end)
	end

	if other then
		map({ 'i', 'n' }, '<F4>', function() vim.cmd.tabedit() end, { desc = 'scan: new tab' })
		map({ 'i', 'n' }, '<F1>', function(bufnr)
			local prompt = M.prompt(bufnr)
			if o.separator then -- grep: keep the pattern only, drop `  -g …`
				prompt = M.split_prompt(prompt, o.separator)
			end
			actions.close(bufnr)
			vim.schedule(function()
				M.switch[other]() {
					root = o.root, cwd = o.cwd, arg_dir = o.arg_dir, one_off = o.one_off, -- arg_dir: keeps 'arg' in the <M-r> cycle
					ignore = o.ignore, hidden = o.hidden, exclude = o.exclude, exclude_files = o.exclude_files,
					ivy = o.ivy, show_preview = o.show_preview, origin_win = o.origin_win, origin_pwd = o.origin_pwd, default_text = prompt,
					file_ignore_patterns = o.file_ignore_patterns,
				}
			end)
		end, { desc = 'scan: switch between live grep and find' })
	end

	if command then
		map({ 'i', 'n' }, '<M-c>', function(bufnr)
			M.show_command(bufnr, command(M.prompt(bufnr)), o.cwd)
		end, { desc = 'scan: show command (y copies)' })
	end

	map({ 'i', 'n' }, '<M-C>', function(bufnr)
		reopen(bufnr, { binary = M.after(o.binary, o.bin) })
	end, { desc = 'scan: next command in the binary list' })

	map({ 'i', 'n' }, '<C-p>', function(bufnr)
		o.show_preview = not o.show_preview -- remembered for <M-r>/<M-i> reopen and <F1> switch
		require('telescope.actions.layout').toggle_preview(bufnr)
	end, { desc = 'scan: toggle preview' })

	map({ 'i', 'n' }, '<M-r>', function(bufnr)
		reopen(bufnr, { root = M.cycle(M.root_cycle(o), o.root), cwd = false, one_off = false })
	end, { desc = 'scan: cycle root pwd/git/bufdir/home' })

	-- one-off: the parent dir isn't added to the <M-r> cycle; <M-r> goes on from o.root
	map({ 'i', 'n' }, '<M-Up>', function(bufnr)
		local dir = vim.fs.normalize(o.cwd):gsub('/$', '')
		local parent = vim.fs.dirname(dir)
		if not parent or same_dir(parent, dir) then
			vim.notify(SRC .. 'already at the top: ' .. M.display_path(dir), vim.log.levels.INFO)
			return
		end
		reopen(bufnr, { cwd = parent, one_off = true })
	end, { desc = 'scan: parent dir (one-off)' })

	map({ 'i', 'n' }, '<M-i>', function(bufnr)
		reopen(bufnr, { ignore = M.cycle(M.ignores, o.ignore) })
	end, { desc = 'scan: cycle gitignore+/vend+mods+dist/unrestricted' })

	-- genja-finder.refine's <M-f> filter, <BS> undo and <M-n> exact match, with a sorter per picker
	local refine = require('genja-finder.refine')
	refine.attach(map, {
		sorter = function()
			local conf = require('telescope.config').values
			if o.separator then -- grep: file + line text
				return conf.generic_sorter(o)
			end
			return conf.file_sorter(o)
		end,
		-- grep: rg matches the pattern, and the prompt holds rg flags; exact applies only after <M-f>
		exact_allowed = function(bufnr)
			return not o.separator or refine.filtered(bufnr) ~= nil
		end,
	})
end

return M
