
-- genja-finder.scope: shared scope togglers for live grep (genja-finder.grep) and live find (genja-finder.find):
-- where the scan starts (<M-r>), what it skips (<M-i>), and the titles that show both.
--
--         <M-r> cycle root (pwd > …/.git > bufdir > home), shown as `from:<root>`,
--         <M-i> cycle what is excluded from the scan (gitignore+ > vend+mods+dist > unrestricted):
--               gitignore+     (default) skips what .gitignore/.ignore list, plus node_modules, vendor and dist
--                              and *.min.js / *.min.css files (`exclude`, `exclude_files`).
--               vend+mods+dist skips only those dirs and *.min.js / *.min.css; paths in .gitignore are searched.
--               unrestricted   skips nothing (--no-ignore), vendor/, node_modules/ and dist/ are searched too.
--               .git is excluded in all modes. Backends that can't read .gitignore (grep, ack)
--               treat gitignore+ as vend+mods+dist.
--         <F1>  switch between live grep and live find, keeping root, skip and the search text.
--         <M-c> popup with the command being run; `y` copies it to the clipboard, <M-c> closes it.
--         <C-p> toggle the preview (off by default; replaces telescope's <C-p> = previous item).

---@alias genja-finder.ScanRoot 'pwd'|'git'|'bufdir'|'home'
---@alias genja-finder.ScanIgnore 'gitignore+'|'vend+mods+dist'|'unrestricted'

---The `map` that telescope passes to attach_mappings(prompt_bufnr, map).
---@alias genja-finder.TelescopeMap fun(mode: 'i'|'n'|('i'|'n')[], lhs: string, action: string|table|fun(prompt_bufnr: integer), opts?: vim.keymap.set.Opts)

---Options shared by the live pickers.
---@class genja-finder.ScanOpts
---@field binary? string|string[]  binaries tried in PATH, first found wins
---@field backend? string          builder to use, if the binary name isn't a known one
---@field root? genja-finder.ScanRoot     where the scan starts (default 'pwd')
---@field cwd? string|false        explicit directory, overrides root
---@field hidden? boolean          include dotfiles (default true)
---@field ignore? genja-finder.ScanIgnore what is excluded from the scan (default 'gitignore+')
---@field exclude? string[]        names excluded in 'gitignore+' and 'vend+mods+dist' (default node_modules, vendor, dist)
---@field exclude_files? string[]  file globs excluded in the same states (default *.min.js, *.min.css)
---@field default_text? string     initial prompt
---@field ivy? boolean             ivy bottom pane layout, the old finn look (default true)
---@field show_preview? boolean    show the preview when the picker opens (default false, <C-p> toggles)
---@field attach? fun(map: genja-finder.TelescopeMap) extra picker keys, e.g. your own shared mappings
---@field origin_win? integer      window the picker was opened from (set internally, kept on reopen)
---@field origin_pwd? string       :pwd when the picker was first opened (set internally, kept on reopen)

local M = {}

---@type genja-finder.ScanOpts
M.defaults = {
	root = 'pwd',
	hidden = true,
	ignore = 'gitignore+',
	exclude = { 'node_modules', 'vendor', 'dist' },
	exclude_files = { '*.min.js', '*.min.css' },
	ivy = true,
	show_preview = false, -- not `preview`: that key is telescope's own preview config
}

---@type genja-finder.ScanRoot[]
M.roots = {
	'pwd',    -- Neovim's working directory (:pwd), same as builtin live_grep. Scans everything below it.
	'git',    -- shown as `…/.git`: nearest parent of the current file (or of pwd) holding .git,
	          -- scans the whole repo even when :pwd is a subfolder. Falls back to pwd outside a repo.
	'bufdir', -- folder of the current buffer's file: narrowest scan, that folder and below only.
	          -- Falls back to pwd for non-file buffers (help, oil, terminal).
	'home',   -- user home dir ($HOME): widest scan, slow without a filter or the gitignore+ skip.
}

---Title text per root, where it differs from the name.
---@type table<genja-finder.ScanRoot, string>
M.root_labels = { git = '…/.git' }

---@type genja-finder.ScanIgnore[]
M.ignores = {
	'gitignore+',     -- .gitignore/.ignore rules + `exclude` (node_modules, vendor, dist)
	'vend+mods+dist', -- only `exclude`; .gitignore'd paths are searched (--no-ignore)
	'unrestricted',   -- nothing excluded but .git (--no-ignore)
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

---First binary of `bins` found in PATH.
---@param bins string|string[]
---@return string? exe full path
---@return string? name binary without dir and extension
function M.find_binary(bins)
	local list = bins
	if type(bins) == 'string' then
		list = { bins }
	end
	for _, b in ipairs(list) do
		local exe = vim.fn.exepath(b)
		if exe ~= '' then return exe, vim.fn.fnamemodify(b, ':t:r') end
	end
end

---Scan dir for `root`, seen from window `win` (its :pwd and its buffer).
---@param root genja-finder.ScanRoot
---@param win integer
---@return string dir
function M.resolve_root(root, win)
	local cwd = vim.fn.getcwd(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local name = vim.api.nvim_buf_get_name(buf)
	local is_file = name ~= '' and vim.bo[buf].buftype == ''
	if root == 'bufdir' then
		return is_file and vim.fs.dirname(name) or cwd
	elseif root == 'git' then
		return vim.fs.root(is_file and name or cwd, '.git') or cwd
	elseif root == 'home' then
		return vim.env.HOME or vim.uv.os_homedir() or cwd
	end
	return cwd
end

---Full path, or `…\a\b\c` (last three components) when longer than 80 chars
---or wider than the current window (minus `reserved` columns).
---@param path string
---@param reserved? integer columns already used by the rest of the title
---@return string
function M.short_path(path, reserved)
	local room = vim.api.nvim_win_get_width(0) - (reserved or 0)
	if #path <= 80 and vim.fn.strdisplaywidth(path) <= room then
		return path
	end
	local sep = path:find('\\', 1, true) and '\\' or '/'
	local parts = vim.split(path, '[\\/]', { trimempty = true })
	if #parts <= 3 then return path end
	return '…' .. sep .. table.concat(parts, sep, #parts - 2)
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

---Current prompt text of the picker in `bufnr`, read from that prompt buffer itself
---(not from whatever buffer is current), without the prompt prefix.
---@param bufnr integer prompt buffer, as passed to the mapping
---@return string
function M.prompt(bufnr)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)
	local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
	local prefix = picker and picker.prompt_prefix or ''
	if prefix ~= '' and line:sub(1, #prefix) == prefix then line = line:sub(#prefix + 1) end
	return line
end

---Pin the origin window and resolve `o.cwd` from `o.root`. Call before building the picker.
---@param o genja-finder.ScanOpts
function M.prepare(o)
	-- resolve roots against the window we came from, not whatever is current during a reopen
	if not (o.origin_win and vim.api.nvim_win_is_valid(o.origin_win)) then
		o.origin_win = vim.api.nvim_get_current_win()
	end
	o.origin_pwd = o.origin_pwd or vim.fn.getcwd(o.origin_win)
	o.cwd = o.cwd or M.resolve_root(o.root, o.origin_win)
end

---Prompt title `<label> <:pwd at first open>` and results title `from:<root> <path> skip:<ignore>`.
---@param o genja-finder.ScanOpts
---@param label string e.g. 'recurseinteractive rg text-scan'
---@return string prompt_title
---@return string results_title
function M.titles(o, label)
	label = label .. ' '
	local from = 'from:' .. (M.root_labels[o.root] or o.root) .. ' '
	local skip = ' skip:' .. o.ignore
	return label .. M.short_path(o.origin_pwd, vim.fn.strdisplaywidth(label)),
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
	if vim.api.nvim_win_is_valid(p.win) then vim.api.nvim_win_close(p.win, true) end
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
	local lines = { line, '', 'in: ' .. cwd, '', cmd and 'y: copy to clipboard    <M-c>: close' or '<M-c>: close' }
	local height = 0
	for _, l in ipairs(lines) do height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(l) / width)) end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].bufhidden = 'wipe'
	local win = vim.api.nvim_open_win(buf, false, {
		relative = 'editor', style = 'minimal', border = 'rounded', zindex = 200,
		title = ' command ', title_pos = 'center',
		width = width, height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
	})
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

---Call `o.attach(map)` first (user keys), then map the togglers below.
---Map <M-c>: command popup (see show_command), when `command` is given.
---Map <M-r> and <M-i>: each closes the picker and reopens it via `open` with the changed
---option, keeping the prompt text.
---Map <F1>: close and open the other picker (`other`: 'grep' or 'find') with the same
---root, skip, origin window and search text (grep's extra args after the separator are dropped).
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
		map({ 'i', 'n' }, '<F1>', function(bufnr)
			local prompt = M.prompt(bufnr)
			if o.separator then -- grep: keep the pattern only, drop `  -g …`
				prompt = prompt:sub(1, (prompt:find(o.separator, 1, true) or 0) - 1)
			end
			actions.close(bufnr)
			vim.schedule(function()
				M.switch[other]() {
					root = o.root, ignore = o.ignore, hidden = o.hidden, exclude = o.exclude, exclude_files = o.exclude_files,
					ivy = o.ivy, show_preview = o.show_preview, origin_win = o.origin_win, origin_pwd = o.origin_pwd, default_text = prompt,
				}
			end)
		end, { desc = 'scan: switch between live grep and find' })
	end

	if command then
		map({ 'i', 'n' }, '<M-c>', function(bufnr)
			M.show_command(bufnr, command(M.prompt(bufnr)), o.cwd)
		end, { desc = 'scan: show command (y copies)' })
	end

	map({ 'i', 'n' }, '<C-p>', function(bufnr)
		o.show_preview = not o.show_preview -- remembered for <M-r>/<M-i> reopen and <F1> switch
		require('telescope.actions.layout').toggle_preview(bufnr)
	end, { desc = 'scan: toggle preview' })

	map({ 'i', 'n' }, '<M-r>', function(bufnr)
		reopen(bufnr, { root = M.cycle(M.roots, o.root), cwd = false })
	end, { desc = 'scan: cycle root pwd/git/bufdir/home' })
	map({ 'i', 'n' }, '<M-i>', function(bufnr)
		reopen(bufnr, { ignore = M.cycle(M.ignores, o.ignore) })
	end, { desc = 'scan: cycle gitignore+/vend+mods+dist/unrestricted' })
end

return M
