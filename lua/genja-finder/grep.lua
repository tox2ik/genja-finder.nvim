
-- genja-finder.grep (live grep): custom telescope live interactive full text search with rg, ack, grep, …
-- Backends: rg, ack, GNU grep. The first one of `binary` found in PATH is used (see grep_builders).
-- Prompt syntax: `pattern  -g *.lua -t php`  (two spaces split the pattern from extra args,
-- which go to the backend as typed, so they must be that backend's flags).
--
-- In the picker:
--
--         <M-r>, <M-i>, <F1>, <M-c>, <C-p>: see genja-finder/scope.lua (shared with live find).
--         <M-g> cycle a file filter after the pattern (text > make > web > js > sys > shell > none),
--               see `filters` in M.defaults. It is written as the backend's own flags:
--               rg    `foo  -g *.{md,txt}`
--               grep  `foo  --include=*.md --include=*.txt`
--               ack   `foo  --type-set=gx:ext:md,txt --type=gx`
--               Other extra args you typed after the filter are kept. Filters by hand work the same:
--               rg `-g !*.min.js` skips files, grep has --exclude=GLOB, `ack --help-types` lists ack types.

local tg = require 'genja-finder.scope'

---A named set of file globs, cycled with <M-g>.
---@class genja-finder.GrepFilter
---@field name string
---@field globs string[]  `*.ext` or a basename glob like `[Mm]akefile*`

---binary defaults to rg, ack, grep; `backend` e.g. 'ggrep' -> 'grep'; `hidden` is rg only.
---@class genja-finder.GrepOpts : genja-finder.ScanOpts
---@field extra_args? string[]     always passed to the backend
---@field separator? string        splits pattern from extra args in the prompt (default '  ')
---@field min_chars? integer       pattern length before the search runs (default 2)
---@field filters? genja-finder.GrepFilter[] file filters cycled with <M-g>

local M = {}

---Grep-only defaults; merged over scope.defaults on each call (setup() can change both).
---@type genja-finder.GrepOpts
M.defaults = {
	binary = { 'rg', 'ack', 'grep' },
	extra_args = {},
	separator = '  ',
	min_chars = 2,
	filters = {
		{ name = 'text',  globs = { '*.md', '*.txt' } },
		{ name = 'make',  globs = { '[Mm]akefile*' } },
		{ name = 'web',   globs = { '*.php', '*.html', '*.htm' } },
		{ name = 'js',    globs = { '*.js', '*.mjs', '*.cjs', '*.jsx', '*.ts', '*.tsx', '*.json' } },
		{ name = 'sys',   globs = { '*.go', '*.c', '*.h', '*.cpp', '*.hpp', '*.cc' } },
		{ name = 'shell', globs = { '*.sh', '*.bash', '*.zsh', '*.fish', '*.ps', '*.ps1', '*.bat' } },
	},
}

---`*.ext` globs folded into one `*.{a,b}` (rg brace syntax); other globs kept as they are.
---@param globs string[]
---@return string[]
local function fold_globs(globs)
	local exts, out = {}, {}
	for _, g in ipairs(globs) do
		local e = g:match '^%*%.([%w_]+)$'
		if e then exts[#exts + 1] = e else out[#out + 1] = g end
	end
	if #exts == 1 then table.insert(out, 1, '*.' .. exts[1])
	elseif #exts > 1 then table.insert(out, 1, '*.{' .. table.concat(exts, ',') .. '}') end
	return out
end

---Glob to Perl regex, for ack's `match:` filter (`*` -> `.*`, `?` -> `.`, [..] kept).
---@param g string
---@return string
local function glob_to_regex(g)
	return (g:gsub('[%.%+%(%)%^%$|{}]', '\\%0'):gsub('%*', '.*'):gsub('%?', '.'))
end

---One backend: how to turn options + prompt into a command line.
---@class genja-finder.GrepBuilder
---@field filter fun(globs: string[]): string file filter as this backend's flags (for <M-g>)
---@field column boolean output is file:line:col:text (false: file:line:text)
---@field base fun(exe: string, o: genja-finder.GrepOpts): string[] fixed part of the command
---@field tail fun(pat: string): string[] args after the prompt's extra args

---Command builders, keyed by binary name without extension.
---@type table<string, genja-finder.GrepBuilder>
local grep_builders = {
	-- ripgrep: honours .gitignore, has --hidden, --smart-case and --column.
	rg = {
		filter = function(globs)
			return table.concat(vim.tbl_map(function(g) return '-g ' .. g end, fold_globs(globs)), ' ')
		end,
		column = true,
		base = function(exe, o)
			local cmd = { exe, '--color=never', '--no-heading', '--with-filename',
				'--line-number', '--column', '--smart-case', '--glob', '!.git' }
			if o.hidden then cmd[#cmd + 1] = '--hidden' end
			if o.ignore ~= 'gitignore+' then cmd[#cmd + 1] = '--no-ignore' end
			if o.ignore ~= 'unrestricted' then
				for _, d in ipairs(o.exclude) do vim.list_extend(cmd, { '--glob', '!' .. d }) end
				for _, f in ipairs(o.exclude_files) do vim.list_extend(cmd, { '--glob', '!' .. f }) end
			end
			return cmd
		end,
		tail = function(pat) return { '--', pat } end,
	},
	-- GNU grep: no .gitignore support (gitignore+ acts like vend+mods+dist), no column (col 1 is used),
	-- always searches dotfiles, ERE regex (-E). Smart case is emulated with -i.
	grep = {
		filter = function(globs)
			return table.concat(vim.tbl_map(function(g) return '--include=' .. g end, globs), ' ')
		end,
		column = false,
		base = function(exe, o)
			local cmd = { exe, '-r', '-n', '-H', '-I', '-E', '--color=never', '--exclude-dir=.git' }
			if o.ignore ~= 'unrestricted' then
				for _, d in ipairs(o.exclude) do cmd[#cmd + 1] = '--exclude-dir=' .. d end
				for _, f in ipairs(o.exclude_files) do cmd[#cmd + 1] = '--exclude=' .. f end
			end
			return cmd
		end,
		tail = function(pat)
			local cmd = pat:find '%u' and {} or { '-i' }
			return vim.list_extend(cmd, { '--', pat, '.' })
		end,
	},
	-- ack: no .gitignore support (gitignore+ acts like vend+mods+dist), skips VCS dirs and its own default
	-- dirs (node_modules, …). Perl regex. --nofilter keeps it from reading stdin.
	ack = {
		-- defines a throwaway type `gx`: --type-set for the first rule, --type-add for the rest
		filter = function(globs)
			local exts, rules = {}, {}
			for _, g in ipairs(globs) do
				local e = g:match '^%*%.([%w_]+)$'
				if e then exts[#exts + 1] = e
				else rules[#rules + 1] = 'match:/^' .. glob_to_regex(g) .. '$/' end
			end
			if #exts > 0 then table.insert(rules, 1, 'ext:' .. table.concat(exts, ',')) end
			local out = {}
			for i, r in ipairs(rules) do
				out[#out + 1] = (i == 1 and '--type-set=gx:' or '--type-add=gx:') .. r
			end
			out[#out + 1] = '--type=gx'
			return table.concat(out, ' ')
		end,
		column = true,
		base = function(exe, o)
			local cmd = { exe, '--nocolor', '--nopager', '--noheading', '--nobreak',
				'--with-filename', '--column', '--smart-case', '--nofilter' }
			local flag = o.ignore == 'unrestricted' and '--noignore-dir=' or '--ignore-dir='
			for _, d in ipairs(o.exclude) do cmd[#cmd + 1] = flag .. d end
			-- ack already skips minified js/css by default, even in unrestricted
			if o.ignore ~= 'unrestricted' then
				for _, f in ipairs(o.exclude_files) do
					cmd[#cmd + 1] = '--ignore-file=match:/^' .. glob_to_regex(f) .. '$/'
				end
			end
			return cmd
		end,
		tail = function(pat) return { '--', pat, '.' } end,
	},
}

---Split extra args, honouring "double" and 'single' quotes.
---@param s string
---@return string[]
local function split_args(s)
	local out, i, n = {}, 1, #s
	while i <= n do
		local c = s:sub(i, i)
		if c:match '%s' then
			i = i + 1
		elseif c == '"' or c == "'" then
			local j = s:find(c, i + 1, true) or n + 1
			out[#out + 1] = s:sub(i + 1, j - 1)
			i = j + 1
		else
			local j = s:find('%s', i) or n + 1
			out[#out + 1] = s:sub(i, j - 1)
			i = j
		end
	end
	return out
end

---@param b genja-finder.GrepBuilder
---@param exe string resolved binary path
---@param o genja-finder.GrepOpts
---@return fun(prompt: string): string[]?
local function grep_command_generator(b, exe, o)
	local base = vim.list_extend(b.base(exe, o), o.extra_args)

	return function(prompt)
		if not prompt or prompt == '' then return nil end
		local pat, rest = prompt, nil
		local s = prompt:find(o.separator, 1, true)
		if s then pat, rest = prompt:sub(1, s - 1), prompt:sub(s + #o.separator) end
		if #pat < o.min_chars then return nil end
		local cmd = vim.deepcopy(base)
		if rest then vim.list_extend(cmd, split_args(rest)) end
		return vim.list_extend(cmd, b.tail(pat))
	end
end

---@param opts? genja-finder.GrepOpts
function M.live_grep(opts)
	local action_state = require 'telescope.actions.state'
	local conf = require('telescope.config').values

	---@type genja-finder.GrepOpts
	local o = vim.tbl_extend('force', tg.defaults, M.defaults, opts or {})
	local exe, name = tg.find_binary(o.binary)
	if not exe then
		vim.notify('genja-finder: none of ' .. vim.inspect(o.binary) .. ' found in PATH', vim.log.levels.ERROR)
		return
	end
	local b = grep_builders[o.backend or name]
	if not b then
		vim.notify('genja-finder: no command builder for ' .. name .. ', set opts.backend', vim.log.levels.ERROR)
		return
	end

	tg.prepare(o)

	local entry_maker = require('telescope.make_entry').gen_from_vimgrep(o) -- after o.cwd: paths are relative to it
	if not b.column then
		-- file:line:text -> file:line:1:text, the shape gen_from_vimgrep parses
		local vimgrep = entry_maker
		entry_maker = function(line)
			local f, l, t = line:match '^(.-):(%d+):(.*)$'
			return vimgrep(f and (f .. ':' .. l .. ':1:' .. t) or line)
		end
	end
	local prompt_title, results_title = tg.titles(o, 'recurseinteractive ' .. vim.fn.fnamemodify(exe, ':t:r') .. ' text-scan')

	local gen = grep_command_generator(b, exe, o)

	tg.find(require('telescope.pickers').new(o, vim.tbl_extend('force', tg.look(o), {
		prompt_title = prompt_title,
		results_title = results_title,
		finder = require('telescope.finders').new_job(gen,
			entry_maker, nil, o.cwd),
		previewer = conf.grep_previewer(o),
		-- activity indicator at the end of the prompt (telescope calls this while the job runs)
		get_status_text = function(self, st)
			local pat = self:_get_prompt()
			pat = pat:sub(1, (pat:find(o.separator, 1, true) or 0) - 1)
			if #pat < o.min_chars then return ('type %d+ chars'):format(o.min_chars) end
			local stats = self.stats or {}
			local hits = (stats.processed or 0) - (stats.filtered or 0)
			if st and not st.completed then return ('⟳ %d …'):format(hits) end
			return ('%d hit%s'):format(hits, hits == 1 and '' or 's')
		end,
		sorter = require('telescope.sorters').highlighter_only(o),
		attach_mappings = function(_, map)
			tg.map(map, o, M.live_grep, 'find', gen)
			map('i', '<M-g>', function(bufnr)
				local line = tg.prompt(bufnr)
				local pat, rest = line, ''
				local s = line:find(o.separator, 1, true)
				if s then pat, rest = line:sub(1, s - 1), line:sub(s + #o.separator) end
				-- which filter is in the prompt now: read it back from the text, 0 = none
				local cur = 0
				for i, f in ipairs(o.filters) do
					local t = b.filter(f.globs)
					if rest:sub(1, #t) == t then
						cur, rest = i, vim.trim(rest:sub(#t + 1))
						break
					end
				end
				local nxt = o.filters[cur + 1] -- nil after the last one: no filter
				local args = vim.trim((nxt and b.filter(nxt.globs) or '') .. ' ' .. rest)
				action_state.get_current_picker(bufnr):set_prompt(args == '' and pat or pat .. o.separator .. args)
			end, { desc = 'grep: cycle file filter' })
			return true
		end,
	})), o)
end

return M
