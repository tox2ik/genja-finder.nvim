-- genja-finder.telemap: shared picker keys for any telescope picker (moved here from the config's
-- lua/genja/fn/telemap.lua). Use from attach_mappings: require('genja-finder.telemap').Telemap(map).
-- require('genja-finder').attach_shared_keys(map) maps these plus the refine keys (genja-finder.refine).

---Directory of the selected entry (the entry itself when it is a directory), or nil.
---@return string?
local function entry_dir()
	local entry = require('telescope.actions.state').get_selected_entry()
	if not entry then
		return nil
	end
	local path = entry.path or entry.filename
	if not path and type(entry.value) == 'string' then
		path = entry.value
	end
	if not path or path == '' then
		return nil
	end
	if entry.cwd and vim.fn.isabsolutepath(path) == 0 then
		path = vim.fs.joinpath(entry.cwd, path)
	end
	if vim.fn.isdirectory(path) == 1 then
		return path
	end
	return vim.fn.fnamemodify(path, ':h')
end

---Close the picker and edit the selected entry's directory (oil opens it).
---@param prompt_bufnr integer
local function open_dir(prompt_bufnr)
	local dir = entry_dir()
	require('telescope.actions').close(prompt_bufnr)
	if dir then
		vim.cmd.edit(vim.fn.fnameescape(dir))
	end
end

---Shared picker keys: <esc> closes, <F2>/<F3> move the selection, <C-]> opens the entry's directory.
---@param map genja-finder.TelescopeMap
local function Telemap(map)
	map({ 'i', 'n' }, '<esc>',  require'telescope.actions'.close,                   { desc = 'Telescope: close' })
	map({ 'i', 'n' }, '<C-]>',  open_dir,                                           { desc = 'Telescope: open dirname' })
	map({ 'i', 'n' }, '<F3>',   require'telescope.actions'.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<S-F3>', require'telescope.actions'.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<F2>',   require'telescope.actions'.move_selection_next,     { desc = 'Telescope: next' })
	map({ 'i', 'n' }, '<S-F2>', require'telescope.actions'.move_selection_next,     { desc = 'Telescope: next' })
end

return {
	Telemap = Telemap,
}
