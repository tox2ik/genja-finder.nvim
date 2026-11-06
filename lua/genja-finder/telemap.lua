-- genja-finder.telemap: shared picker keys for any telescope picker (moved here from the config's
-- lua/genja/fn/telemap.lua). Use from attach_mappings: require('genja-finder.telemap').Telemap(map).
-- require('genja-finder').attach_shared_keys(map) maps these plus the refine keys (genja-finder.refine).

local SRC = 'genja-finder/telemap.lua: '

---Path of a telescope entry, joined to its cwd when relative, or nil.
---@param entry table?
---@return string?
local function entry_path(entry)
	if not entry then
		return nil
	end
	local path = entry.path or entry.filename
	if not path and type(entry.value) == 'string' then
		path = entry.value -- e.g. oldfiles, plain string pickers
	end
	if not path or path == '' then
		return nil
	end
	if entry.cwd and vim.fn.isabsolutepath(path) == 0 then
		path = vim.fs.joinpath(entry.cwd, path)
	end
	return path
end

---Selected entry when it is a directory, else its dirname, or nil.
---@return string?
local function selected_entry_dir_or_dirname()
	local path = entry_path(require('telescope.actions.state').get_selected_entry())
	if not path then
		return nil
	end
	if vim.fn.isdirectory(path) == 1 then
		return path
	end
	return vim.fn.fnamemodify(path, ':h')
end

---Close the picker and edit the selected entry's directory (oil opens it).
---@param prompt_bufnr integer
local function open_dir(prompt_bufnr)
	local dir = selected_entry_dir_or_dirname()
	require('telescope.actions').close(prompt_bufnr)
	if dir then
		vim.cmd.edit(vim.fn.fnameescape(dir))
	end
end

---Open the marked entries (else the selected one) in tabs behind the picker, at their line
---when they have one; the picker stays.
---@param prompt_bufnr integer
local function tabedit_selected_keep_picker(prompt_bufnr)
	local action_state = require('telescope.actions.state')
	local entries = action_state.get_current_picker(prompt_bufnr):get_multi_selection()
	if #entries == 0 then
		entries = { action_state.get_selected_entry() }
	end
	local tab = vim.api.nvim_get_current_tabpage()
	local win = vim.api.nvim_get_current_win()
	-- telescope closes the picker on the prompt's BufLeave
	local saved_eventignore = vim.o.eventignore
	vim.opt.eventignore:append('BufLeave')
	local ok, err = pcall(function()
		for _, entry in ipairs(entries) do
			local path = entry_path(entry)
			if path then
				vim.cmd.tabedit(vim.fn.fnameescape(path))
				if entry.lnum then
					pcall(vim.api.nvim_win_set_cursor, 0, { entry.lnum, math.max((entry.col or 1) - 1, 0) })
				end
			end
		end
	end)
	vim.api.nvim_set_current_tabpage(tab)
	vim.api.nvim_set_current_win(win)
	vim.o.eventignore = saved_eventignore
	if not ok then
		vim.notify(SRC .. 'tabedit failed: ' .. tostring(err), vim.log.levels.ERROR)
	end
end

---Shared picker keys: <esc> closes, <F2>/<F3> move the selection, <C-]> opens the entry's directory,
---<M-t> opens the selection in tabs.
---@param map genja-finder.TelescopeMap
local function Telemap(map)
	local actions = require('telescope.actions')
	map({ 'i', 'n' }, '<esc>',  actions.close,                   { desc = 'Telescope: close' })
	map({ 'i', 'n' }, '<C-]>',  open_dir,                        { desc = 'Telescope: open dirname' })
	map({ 'i', 'n' }, '<F3>',   actions.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<S-F3>', actions.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<F2>',   actions.move_selection_next,     { desc = 'Telescope: next' })
	map({ 'i', 'n' }, '<S-F2>', actions.move_selection_next,     { desc = 'Telescope: next' })
	map({ 'i', 'n' }, '<M-t>',  tabedit_selected_keep_picker,    { desc = 'Telescope: open selected in tabs, keep the picker' })
end

return {
	Telemap = Telemap,
}
