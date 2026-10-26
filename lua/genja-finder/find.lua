-- genja-finder.find (live find): custom telescope file finder.
-- Backends: es (Everything, Windows), locate (Linux), fd (fdfind on Debian), rg. The first one of
-- `binary` found in PATH and ready is used (see live_builders, find_builders).
--   es, locate  indexed search, rerun on each keystroke with the prompt as the query
--               (after `min_chars`, at most `max_results` paths). es is skipped when Everything
--               isn't running. The es prompt takes Everything's search syntax (ext:lua, dm:today).
--   fd, rg      fuzzy match over the whole file list, listed once.
-- Layout: ivy bottom pane like the old `Telescope finn` (scope.look; ivy = false: global layout).
-- Preview hidden by default, <C-p> toggles it (file shown from the top).
--
-- In the picker: <M-r>, <M-i>, <F1>, <M-c>, <M-C>, <C-p>, <M-f>, same as live grep (see genja-finder/scope.lua).
--
--         <M-F> popup asking for a file name part: only files whose name contains it are listed
--               (case-insensitive, like find -iname '*part*'), so the fuzzy match runs over far fewer
--               paths: `.ahk` lists only the *.ahk files. With * ? or [ it is a glob as typed (`*.ahk`).
--               Empty input lists everything again. Shown as `name:<part>` in the results title.

local SRC = 'genja-finder/find.lua: '

local scope = require('genja-finder.scope')

---@class genja-finder.FindOpts : genja-finder.ScanOpts
---@field follow? boolean          follow symlinks (default false)
---@field name? string             list only files whose name contains this (<M-F>), a glob if it has * ? [
---@field min_chars? integer       es/locate: query length before the search runs (default 2)
---@field max_results? integer     es/locate: most paths per query (default 15000)

local M = {}

---Find-only defaults; merged over scope.defaults on each call (setup() can change both).
---@type genja-finder.FindOpts
M.defaults = {
	-- binary = { 'es', 'locate', 'fd', 'fdfind', 'rg' },
	binary = { 'es', 'fd', 'fdfind', 'rg' },
	follow = false,
	min_chars = 2,
	max_results = 15000,
}

---`o.name` as a glob: as typed when it has * ? [, else `*name*`. nil when unset.
---@param o genja-finder.FindOpts
---@return string? glob
---@return boolean? typed true when `o.name` was already a glob
local function name_glob(o)
	if not o.name or o.name == '' then return nil end
	if o.name:find '[*?[]' then return o.name, true end
	return '*' .. o.name .. '*', false
end

---Command builders for the file list, keyed by binary name without extension.
---@type table<string, fun(exe: string, o: genja-finder.FindOpts): string[]>
local find_builders = {
	rg = function(exe, o)
		local cmd = { exe, '--files', '--color=never', '--glob', '!.git' }
		if o.hidden then cmd[#cmd + 1] = '--hidden' end
		if o.follow then cmd[#cmd + 1] = '--follow' end
		if o.ignore ~= 'gitignore+' then cmd[#cmd + 1] = '--no-ignore' end
		if o.ignore ~= 'unrestricted' then
			for _, d in ipairs(o.exclude) do vim.list_extend(cmd, { '--glob', '!' .. d }) end
			for _, f in ipairs(o.exclude_files) do vim.list_extend(cmd, { '--glob', '!' .. f }) end
		end
		local glob = name_glob(o)
		if glob then vim.list_extend(cmd, { '--iglob', glob }) end -- no slash: matches the basename at any depth
		return cmd
	end,
	fd = function(exe, o)
		local cmd = { exe, '--type', 'f', '--color', 'never', '--exclude', '.git' }
		if o.hidden then cmd[#cmd + 1] = '--hidden' end
		if o.follow then cmd[#cmd + 1] = '--follow' end
		if o.ignore ~= 'gitignore+' then cmd[#cmd + 1] = '--no-ignore' end
		if o.ignore ~= 'unrestricted' then
			for _, d in ipairs(o.exclude) do vim.list_extend(cmd, { '--exclude', d }) end
			for _, f in ipairs(o.exclude_files) do vim.list_extend(cmd, { '--exclude', f }) end
		end
		local glob, typed = name_glob(o)
		if typed then -- the pattern matches the file name only
			vim.list_extend(cmd, { '--ignore-case', '--glob', '--', glob })
		elseif glob then
			vim.list_extend(cmd, { '--ignore-case', '--fixed-strings', '--', o.name })
		end
		return cmd
	end,
}
find_builders.fdfind = find_builders.fd

---Indexed search, run per keystroke. Neither reads .gitignore: gitignore+ acts like vend+mods+dist.
---@class genja-finder.LiveFindBuilder
---@field ready? fun(exe: string): boolean false: try the next binary
---@field cmd fun(exe: string, o: genja-finder.FindOpts, query: string): string[]

---@type table<string, genja-finder.LiveFindBuilder>
local live_builders = {
	es = {
		ready = function(exe)
			-- exits non-zero when Everything isn't running (no IPC window)
			local ok, res = pcall(function()
				return vim.system({ exe, '-get-everything-version' }):wait(1000)
			end)
			return ok and res.code == 0
		end,
		cmd = function(exe, o, query)
			-- a term with a backslash matches the full path; /a-d: files only
			local root = o.cwd:gsub('/', '\\')
			local cmd = { exe, '-n', tostring(o.max_results), '/a-d', '-path', root, '!\\.git\\' }
			if o.ignore ~= 'unrestricted' then
				for _, d in ipairs(o.exclude) do
					local dir = d:gsub('^%*%*/', ''):gsub('/', '\\')
					cmd[#cmd + 1] = '!\\' .. dir .. '\\'
				end
				for _, f in ipairs(o.exclude_files) do cmd[#cmd + 1] = '!' .. f end
			end
			local glob = name_glob(o)
			if glob then cmd[#cmd + 1] = glob end
			return vim.list_extend(cmd, vim.split(query, '%s+', { trimempty = true }))
		end,
	},
	locate = {
		cmd = function(exe, o, query)
			-- -A: every word must match, each one below the root
			local root = vim.fs.normalize(o.cwd):gsub('/$', '')
			local cmd = { exe, '-i', '-A', '-l', tostring(o.max_results), '--' }
			for _, w in ipairs(vim.split(query, '%s+', { trimempty = true })) do
				cmd[#cmd + 1] = root .. '/*' .. w .. '*'
			end
			return cmd
		end,
	},
}

---Glob as an lpeg pattern that must match the whole (lowercased) name.
---@param glob string
local function name_pattern(glob)
	return vim.glob.to_lpeg(glob:lower()) * vim.lpeg.P(-1)
end

---Filter for paths from es/locate (relative to the root, / separated): drops .git, `exclude`,
---`exclude_files` and names not matching <M-F>, which locate can't skip. Hidden files and dotfiles stay.
---@param o genja-finder.FindOpts
---@return fun(rel: string): boolean
local function path_filter(o)
	local dirs = { '.git' }
	local files = {}
	if o.ignore ~= 'unrestricted' then
		for _, d in ipairs(o.exclude) do
			dirs[#dirs + 1] = (d:gsub('^%*%*/', ''))
		end
		for _, f in ipairs(o.exclude_files) do files[#files + 1] = name_pattern(f) end
	end
	local glob = name_glob(o)
	local wanted = glob and name_pattern(glob)

	return function(rel)
		local path = '/' .. rel
		for _, d in ipairs(dirs) do
			if path:find('/' .. d .. '/', 1, true) then return false end
		end
		local name = vim.fs.basename(rel):lower()
		for _, p in ipairs(files) do
			if p:match(name) then return false end
		end
		if wanted then return wanted:match(name) ~= nil end
		return true
	end
end

---@param opts? genja-finder.FindOpts
function M.live_find(opts)
	local conf = require('telescope.config').values

	---@type genja-finder.FindOpts
	local o = vim.tbl_extend('force', scope.defaults, M.defaults, opts or {})
	local exe, name = scope.find_binary(o.binary, function(e, n)
		local b = live_builders[o.backend or n]
		if b and b.ready then return b.ready(e) end
		return true
	end)
	if not exe then
		vim.notify(SRC .. 'none of ' .. vim.inspect(o.binary) .. ' found in PATH (or ready)', vim.log.levels.ERROR)
		return
	end
	o.bin = name
	local live = live_builders[o.backend or name]
	local build = find_builders[o.backend or name]
	if not live and not build then
		vim.notify(SRC .. 'no command builder for ' .. name .. ', set opts.backend', vim.log.levels.ERROR)
		return
	end
	scope.prepare(o)

	local prompt_title, results_title = scope.titles(o, 'findz00r ' .. vim.fn.fnamemodify(exe, ':t:r'))
	if o.name and o.name ~= '' then results_title = results_title .. ' name:' .. o.name end

	local file_entry = require('telescope.make_entry').gen_from_file(o) -- o.cwd set: paths relative to it
	local finder, sorter, command, status
	if live then
		local root = vim.fs.normalize(o.cwd):gsub('/$', '') .. '/'
		local keep = path_filter(o)
		command = function(prompt)
			local query = vim.trim(prompt or '')
			if #query < o.min_chars then return nil end
			return live.cmd(exe, o, query)
		end
		-- es/locate print full paths: make them relative to the root, like fd's
		local function entry_maker(line)
			local rel = vim.fs.normalize(line)
			if rel:sub(1, #root):lower() == root:lower() then rel = rel:sub(#root + 1) end
			if not keep(rel) then return nil end
			return file_entry(rel)
		end
		finder = require('telescope.finders').new_job(command, entry_maker, nil, o.cwd)
		sorter = require('telescope.sorters').highlighter_only(o) -- the index already matched
		status = function(self, st)
			local stats = self.stats or {}
			local hits = (stats.processed or 0) - (stats.filtered or 0)
			if scope.filtered(self.prompt_bufnr) then -- <M-f>: fuzzy over the frozen results
				return ('%d of %d'):format(hits, #(self.finder.results or {}))
			end
			if #vim.trim(self:_get_prompt()) < o.min_chars then return ('type %d+ chars'):format(o.min_chars) end
			if st and not st.completed then return ('⟳ %d …'):format(hits) end
			if hits == 1 then return '1 file' end
			return ('%d files'):format(hits)
		end
	else
		local cmd = build(exe, o)
		command = function() return cmd end
		finder = require('telescope.finders').new_oneshot_job(vim.deepcopy(cmd), {
			entry_maker = file_entry,
			cwd = o.cwd,
		})
		sorter = conf.file_sorter(o)
	end

	scope.find(require('telescope.pickers').new(o, vim.tbl_extend('force', scope.look(o), {
		prompt_title = prompt_title,
		results_title = results_title,
		finder = finder,
		previewer = conf.file_previewer(o), -- whole file from the top, hidden until <C-p>
		sorter = sorter,
		get_status_text = status,
		attach_mappings = function(_, map)
			scope.map(map, o, M.live_find, 'grep', command)
			map({ 'i', 'n' }, '<M-F>', function(bufnr)
				local prompt = scope.prompt(bufnr)
				require('telescope.actions').close(bufnr)
				vim.schedule(function()
					scope.ask('file name contains', o.name or '', function(text)
						local patch = { default_text = prompt }
						if text then -- nil: <Esc>, keep the old name
							patch.name = vim.trim(text)
						end
						M.live_find(vim.tbl_extend('force', o, patch))
					end)
				end)
			end, { desc = 'find: list only files whose name contains …' })
			return true
		end,
	})), o)
end

return M
