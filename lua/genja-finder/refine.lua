-- genja-finder.refine: <M-f> filter for any telescope picker, and a decorator that adds it.
--
--         <M-f> freeze the listed results and fuzzy-match within them on a fresh prompt;
--               press again to narrow further. The search moves into the prompt prefix (`foo > `).
--         <BS>  on an empty prompt: undo the last <M-f>, restoring the results and its text.
--
-- In a picker's attach_mappings:  require('genja-finder.refine').attach(map)
-- Around a picker function:       require('genja-finder.refine').decorate(builtin.oldfiles)
-- Both with Telemap's keys:       require('genja-finder').attach_shared_keys(map) / .enhance(picker)

local M = {}

---One <M-f> step: what the picker had before it, restored by <BS> (M.undo).
---@class genja-finder.RefineLevel
---@field finder table     telescope finder (closed by refine; job finders rerun when called again)
---@field sorter table     telescope sorter
---@field prefix string    prompt prefix
---@field title string     prompt title
---@field text string      prompt text, without the prefix

---<M-f> steps per prompt buffer, oldest first.
---@type table<integer, genja-finder.RefineLevel[]>
local levels = {}

---Search text the results of the picker in `bufnr` were frozen with (<M-f>), nil when not filtered.
---@param bufnr integer prompt buffer
---@return string?
function M.filtered(bufnr)
	local stack = levels[bufnr]
	if stack and #stack > 0 then
		return stack[1].text
	end
	return nil
end

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
	if not levels[bufnr] then
		levels[bufnr] = {}
		vim.api.nvim_create_autocmd('BufWipeout', {
			buffer = bufnr, once = true, callback = function() levels[bufnr] = nil end,
		})
	end

	local stack = levels[bufnr]
	local title = picker.prompt_title
	if #stack > 0 then
		title = picker.prompt_title .. ' [filter]'
	end
	table.insert(stack, {
		finder = picker.finder,
		sorter = picker.sorter,
		prefix = picker.prompt_prefix,
		title = title,
		text = M.text(bufnr),
	})

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

---Undo the last <M-f> of the picker in `bufnr`: its finder, sorter, prefix, title and prompt text.
---@param bufnr integer prompt buffer
---@return boolean undone false when nothing was filtered
function M.undo(bufnr)
	local stack = levels[bufnr]
	if not stack or #stack == 0 then
		return false
	end
	local level = table.remove(stack)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)

	if picker.layout.prompt.border then
		picker.layout.prompt.border:change_title(level.title)
	end
	picker.sorter:_destroy()
	picker.sorter = level.sorter
	picker.sorter:_init()
	picker:change_prompt_prefix(level.prefix, 'TelescopePromptPrefix')
	picker.finder:close()
	picker.finder = level.finder
	-- setting the prompt line reruns the finder with that text
	picker:reset_prompt(level.text)
	return true
end

---Map the refine keys: <M-f> filter, <BS> on an empty prompt undoes the last <M-f>.
---@param map genja-finder.TelescopeMap
---@param make_sorter? fun(): table sorter for <M-f>, built at keypress (default: the generic sorter)
function M.attach(map, make_sorter)
	map({ 'i', 'n' }, '<M-f>', function(bufnr)
		local sorter = nil
		if make_sorter then
			sorter = make_sorter()
		end
		M.filter(bufnr, sorter)
	end, { desc = 'refine: filter the listed results (fuzzy, fresh prompt)' })

	map('i', '<BS>', function(bufnr)
		if M.text(bufnr) == '' and M.undo(bufnr) then
			return
		end
		vim.api.nvim_feedkeys(vim.keycode('<BS>'), 'n', false)
	end, { desc = 'refine: undo the last filter on an empty prompt, else delete a character' })
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
