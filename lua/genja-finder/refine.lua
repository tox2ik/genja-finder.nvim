-- genja-finder.refine: <M-f> filter for any telescope picker, and a decorator that adds it.
--
--         <M-f> freeze the listed results and fuzzy-match within them on a fresh prompt;
--               press again to narrow further. The search moves into the prompt prefix (`foo > `).
--
-- In a picker's attach_mappings:  require('genja-finder.refine').attach(map)
-- Around a picker function:       require('genja-finder.refine').decorate(builtin.oldfiles)
-- Both with Telemap's keys:       require('genja-finder').attach_shared_keys(map) / .enhance(picker)

local M = {}

---Search text the results were frozen with by <M-f>, by prompt buffer.
---@type table<integer, string>
local frozen = {}

---Search text the results of the picker in `bufnr` were frozen with (<M-f>), nil when not filtered.
---@param bufnr integer prompt buffer
---@return string?
function M.filtered(bufnr) return frozen[bufnr] end

---Prompt text of the picker in `bufnr`, read from that prompt buffer itself, without the prompt prefix.
---@param bufnr integer prompt buffer
---@return string
function M.text(bufnr)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)
	local line = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ''
	local prefix = ''
	if picker and picker.prompt_prefix then
		prefix = picker.prompt_prefix
	end
	if prefix ~= '' and line:sub(1, #prefix) == prefix then
		line = line:sub(#prefix + 1)
	end
	return line
end

---Filter the listed results of the picker in `bufnr`: fuzzy match on a fresh prompt.
---The first call remembers the search (see M.filtered); later calls narrow further.
---@param bufnr integer prompt buffer
---@param sorter? table telescope sorter (default: the generic sorter)
function M.filter(bufnr, sorter)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)
	if not frozen[bufnr] then
		frozen[bufnr] = M.text(bufnr)
		vim.api.nvim_create_autocmd('BufWipeout', {
			buffer = bufnr, once = true, callback = function() frozen[bufnr] = nil end,
		})
	end

	if not sorter then
		sorter = require('telescope.config').values.generic_sorter({})
	end

	-- the typed text moves into the prompt prefix (`foo > `), so stacked filters show as `foo > bar > `
	require('telescope.actions.generate').refine(bufnr, {
		prompt_title = picker.prompt_title .. ' [filter]',
		prompt_to_prefix = true,
		sorter = sorter,
	})
end

---Map the refine keys: <M-f> filter.
---@param map genja-finder.TelescopeMap
function M.attach(map)
	map({ 'i', 'n' }, '<M-f>', function(bufnr) M.filter(bufnr) end,
		{ desc = 'refine: filter the listed results (fuzzy, fresh prompt)' })
end

---Wrap a picker function (e.g. telescope.builtin.oldfiles) so it opens with extra keys.
---Telescope runs a caller's opts.attach_mappings after the picker's own, so both apply.
---Pickers that don't pass their opts to pickers.new get nothing; call attach(map) inside them.
---@param picker fun(opts?: table) picker function that takes telescope opts
---@param attach? fun(map: genja-finder.TelescopeMap) keys to add (default M.attach)
---@return fun(opts?: table)
function M.decorate(picker, attach)
	if not attach then
		attach = M.attach
	end
	return function(opts)
		opts = vim.deepcopy(opts or {})
		local caller = opts.attach_mappings
		opts.attach_mappings = function(bufnr, map)
			attach(map)
			if caller then
				return caller(bufnr, map)
			end
			return true
		end
		return picker(opts)
	end
end

return M
