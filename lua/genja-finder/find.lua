
-- genja-finder.find (live find): custom telescope file finder, fuzzy match over the file list from fd or rg --files.
-- Backends: fd (fdfind on Debian), rg. The first one of `binary` found in PATH is used (see find_builders).
-- Layout: ivy bottom pane like the old `Telescope finn` (tg.look; ivy = false: global layout).
-- Preview hidden by default, <C-p> toggles it (file shown from the top).
--
-- In the picker: <M-r>, <M-i>, <F1>, <M-c>, <C-p>, <M-F>, same as live grep (see genja-finder/scope.lua).
--
--         <M-f> popup asking for a file name part: only files whose name contains it are listed
--               (case-insensitive, like find -iname '*part*'), so the fuzzy match runs over far fewer
--               paths: `.ahk` lists only the *.ahk files. With * ? or [ it is a glob as typed (`*.ahk`).
--               Empty input lists everything again. Shown as `name:<part>` in the results title.

local tg = require 'genja-finder.scope'

---@class genja-finder.FindOpts : genja-finder.ScanOpts
---@field follow? boolean          follow symlinks (default false)
---@field name? string             list only files whose name contains this (<M-f>), a glob if it has * ? [

local M = {}

---Find-only defaults; merged over scope.defaults on each call (setup() can change both).
---@type genja-finder.FindOpts
M.defaults = {
	binary = { 'fd', 'fdfind', 'rg' },
	follow = false,
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

---Command builders, keyed by binary name without extension.
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
		if glob then -- the pattern matches the file name only
			vim.list_extend(cmd, typed and { '--ignore-case', '--glob', '--', glob }
				or { '--ignore-case', '--fixed-strings', '--', o.name })
		end
		return cmd
	end,
}
find_builders.fdfind = find_builders.fd

---@param opts? genja-finder.FindOpts
function M.live_find(opts)
	local conf = require('telescope.config').values

	---@type genja-finder.FindOpts
	local o = vim.tbl_extend('force', tg.defaults, M.defaults, opts or {})
	local exe, name = tg.find_binary(o.binary)
	if not exe then
		vim.notify('genja-finder: none of ' .. vim.inspect(o.binary) .. ' found in PATH', vim.log.levels.ERROR)
		return
	end
	local build = find_builders[o.backend or name]
	if not build then
		vim.notify('genja-finder: no command builder for ' .. name .. ', set opts.backend', vim.log.levels.ERROR)
		return
	end
	tg.prepare(o)

	local prompt_title, results_title = tg.titles(o, 'findz00r ' .. vim.fn.fnamemodify(exe, ':t:r'))
	if o.name and o.name ~= '' then results_title = results_title .. ' name:' .. o.name end

	local cmd = build(exe, o)

	tg.find(require('telescope.pickers').new(o, vim.tbl_extend('force', tg.look(o), {
		prompt_title = prompt_title,
		results_title = results_title,
		finder = require('telescope.finders').new_oneshot_job(vim.deepcopy(cmd), {
			entry_maker = require('telescope.make_entry').gen_from_file(o), -- o.cwd set: paths relative to it
			cwd = o.cwd,
		}),
		previewer = conf.file_previewer(o), -- whole file from the top, hidden until <C-p>
		sorter = conf.file_sorter(o),
		attach_mappings = function(_, map)
			tg.map(map, o, M.live_find, 'grep', function() return cmd end)
			map({ 'i', 'n' }, '<M-f>', function(bufnr)
				local prompt = tg.prompt(bufnr)
				require('telescope.actions').close(bufnr)
				vim.schedule(function()
					tg.ask('file name contains', o.name or '', function(text)
						M.live_find(vim.tbl_extend('force', o, { default_text = prompt }, text and { name = vim.trim(text) } or {}))
					end)
				end)
			end, { desc = 'find: list only files whose name contains …' })
			return true
		end,
	})), o)
end

return M
