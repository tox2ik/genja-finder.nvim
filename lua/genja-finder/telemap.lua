-- genja-finder.telemap: shared picker keys for any telescope picker (moved here from the config's
-- lua/genja/fn/telemap.lua). Use from attach_mappings: require('genja-finder.telemap').Telemap(map).
-- require('genja-finder').attach_shared_keys(map) maps these plus the refine keys (genja-finder.refine).

---Shared picker keys: <esc> closes, <F2>/<F3> move the selection.
---@param map genja-finder.TelescopeMap
local function Telemap(map)
	map({ 'i', 'n' }, '<esc>',  require'telescope.actions'.close,                   { desc = 'Telescope: close' })
	map({ 'i', 'n' }, '<F3>',   require'telescope.actions'.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<S-F3>', require'telescope.actions'.move_selection_previous, { desc = 'Telescope: prev' })
	map({ 'i', 'n' }, '<F2>',   require'telescope.actions'.move_selection_next,     { desc = 'Telescope: next' })
	map({ 'i', 'n' }, '<S-F2>', require'telescope.actions'.move_selection_next,     { desc = 'Telescope: next' })
end

return {
	Telemap = Telemap,
}
