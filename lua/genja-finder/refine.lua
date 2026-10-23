-- genja-finder.refine: <M-f> filter for any telescope picker, and a decorator that adds it.
--
--         <M-f> freeze the listed results and fuzzy-match within them on a fresh prompt;
--               press again to narrow further. The search moves into the prompt prefix (`foo > `).
--         <BS>  on an empty prompt: undo the last <M-f>, restoring the results and its text.
--         <M-n> switch between fuzzy and exact match (each word as typed); new <M-f> levels
--               start in the current mode, <BS> undo restores the mode of the earlier level.
--
-- In a picker's attach_mappings:  require('genja-finder.refine').attach(map)
-- Around a picker function:       require('genja-finder.refine').decorate(builtin.oldfiles)
-- Both with Telemap's keys:       require('genja-finder').attach_shared_keys(map) / .enhance(picker)

local SRC = 'genja-finder/refine.lua: '

local M = {}

---One <M-f> step: what the picker had before it, restored by <BS> (M.undo).
---@class genja-finder.RefineLevel
---@field finder table     telescope finder (closed by refine; job finders rerun when called again)
---@field sorter table     telescope sorter
---@field prefix string    prompt prefix
---@field text string      prompt text, without the prefix
---@field exact boolean    <M-n> exact match was on
---@field fuzzy? table     the fuzzy sorter to return to, while exact was on

---Exact match state (<M-n>) of one picker.
---@class genja-finder.RefineMode
---@field exact boolean    exact match on
---@field fuzzy? table     the fuzzy sorter that <M-n> switches back to

---Options of M.attach.
---@class genja-finder.RefineOpts
---@field sorter? fun(): table          fuzzy sorter for <M-f>, built at keypress (default: the generic sorter)
---@field exact_allowed? fun(bufnr: integer): boolean  false: <M-n> only notifies (live grep before <M-f>)

---<M-f> steps per prompt buffer, oldest first.
---@type table<integer, genja-finder.RefineLevel[]>
local levels = {}

---<M-n> state per prompt buffer.
---@type table<integer, genja-finder.RefineMode>
local modes = {}

---Level stack and mode of the picker in `bufnr`, created on first use, dropped with the buffer.
---@param bufnr integer prompt buffer
---@return genja-finder.RefineLevel[] stack
---@return genja-finder.RefineMode mode
local function state(bufnr)
	if not levels[bufnr] then
		levels[bufnr] = {}
		modes[bufnr] = { exact = false }
		vim.api.nvim_create_autocmd('BufWipeout', {
			buffer = bufnr, once = true,
			callback = function()
				levels[bufnr] = nil
				modes[bufnr] = nil
			end,
		})
	end
	return levels[bufnr], modes[bufnr]
end

---Prompt title for the current state: `[filter]` after <M-f>, `[exact]` while <M-n> is on.
---@param picker table
---@param bufnr integer prompt buffer
---@return string
local function title(picker, bufnr)
	local stack, mode = state(bufnr)
	local text = picker.prompt_title
	if #stack > 0 then
		text = text .. ' [filter]'
	end
	if mode.exact then
		text = text .. ' [exact]'
	end
	return text
end

---Show the title for the current state in the prompt border.
---@param picker table
---@param bufnr integer prompt buffer
local function show_title(picker, bufnr)
	if picker.layout.prompt.border then
		picker.layout.prompt.border:change_title(title(picker, bufnr))
	end
end

---Replace the picker's sorter (the old one stays usable: _init runs again when it comes back).
---@param picker table
---@param sorter table
local function use_sorter(picker, sorter)
	if picker.sorter then
		picker.sorter:_destroy()
	end
	picker.sorter = sorter
	picker.sorter:_init()
end

---The fuzzy sorter: `make_sorter()` when given, else telescope's generic sorter.
---@param make_sorter? fun(): table
---@return table
local function fuzzy_sorter(make_sorter)
	if make_sorter then
		return make_sorter()
	end
	return require('telescope.config').values.generic_sorter({})
end

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

---Filter the listed results of the picker in `bufnr` on a fresh prompt: fuzzy, or exact while <M-n> is on.
---The first call remembers the search (see M.filtered); later calls narrow further.
---@param bufnr integer prompt buffer
---@param sorter? table fuzzy sorter (default: the generic sorter)
function M.filter(bufnr, sorter)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)
	local stack, mode = state(bufnr)
	table.insert(stack, {
		finder = picker.finder,
		sorter = picker.sorter,
		prefix = picker.prompt_prefix,
		text = M.text(bufnr),
		exact = mode.exact,
		fuzzy = mode.fuzzy,
	})

	if not sorter then
		sorter = fuzzy_sorter()
	end
	-- the new level starts in the current mode; its fuzzy sorter is kept for <M-n>
	if mode.exact then
		mode.fuzzy = sorter
		sorter = require('telescope.sorters').get_substr_matcher()
	end

	-- the typed text moves into the prompt prefix (`foo > `), so stacked filters show as `foo > bar > `
	require('telescope.actions.generate').refine(bufnr, {
		prompt_title = title(picker, bufnr),
		prompt_to_prefix = true,
		sorter = sorter,
	})
end

---Undo the last <M-f> of the picker in `bufnr`: its finder, sorter, mode, prefix, title and prompt text.
---@param bufnr integer prompt buffer
---@return boolean undone false when nothing was filtered
function M.undo(bufnr)
	local stack, mode = state(bufnr)
	if #stack == 0 then
		return false
	end
	local level = table.remove(stack)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)

	mode.exact = level.exact
	mode.fuzzy = level.fuzzy
	show_title(picker, bufnr)
	use_sorter(picker, level.sorter)
	picker:change_prompt_prefix(level.prefix, 'TelescopePromptPrefix')
	picker.finder:close()
	picker.finder = level.finder
	-- setting the prompt line reruns the finder with that text
	picker:reset_prompt(level.text)
	return true
end

---Switch the picker in `bufnr` between fuzzy and exact match (telescope's substring matcher:
---every space-separated word must appear as typed; smartcase), then rerun the current prompt.
---@param bufnr integer prompt buffer
---@param make_sorter? fun(): table fuzzy sorter, when none was kept (default: the generic sorter)
function M.toggle_exact(bufnr, make_sorter)
	local picker = require('telescope.actions.state').get_current_picker(bufnr)
	local _, mode = state(bufnr)
	if mode.exact then
		local fuzzy = mode.fuzzy
		if not fuzzy then
			fuzzy = fuzzy_sorter(make_sorter)
		end
		use_sorter(picker, fuzzy)
		mode.exact = false
		mode.fuzzy = nil
	else
		mode.fuzzy = picker.sorter
		use_sorter(picker, require('telescope.sorters').get_substr_matcher())
		mode.exact = true
	end
	show_title(picker, bufnr)
	picker:refresh(nil, { reset_prompt = false })
end

---Map the refine keys: <M-f> filter, <BS> on an empty prompt undoes the last <M-f>,
---<M-n> switches between fuzzy and exact match.
---@param map genja-finder.TelescopeMap
---@param opts? genja-finder.RefineOpts
function M.attach(map, opts)
	opts = opts or {}

	map({ 'i', 'n' }, '<M-f>', function(bufnr)
		local sorter = nil
		if opts.sorter then
			sorter = opts.sorter()
		end
		M.filter(bufnr, sorter)
	end, { desc = 'refine: filter the listed results (fresh prompt)' })

	map('i', '<BS>', function(bufnr)
		if M.text(bufnr) == '' and M.undo(bufnr) then
			return
		end
		vim.api.nvim_feedkeys(vim.keycode('<BS>'), 'n', false)
	end, { desc = 'refine: undo the last filter on an empty prompt, else delete a character' })

	map({ 'i', 'n' }, '<M-n>', function(bufnr)
		if opts.exact_allowed and not opts.exact_allowed(bufnr) then
			vim.notify(SRC .. 'exact match works on filtered results; press <M-f> first', vim.log.levels.INFO)
			return
		end
		M.toggle_exact(bufnr, opts.sorter)
	end, { desc = 'refine: switch between fuzzy and exact match' })
end

---Wrap a picker function (e.g. telescope.builtin.oldfiles) so it opens with extra keys.
---Telescope runs a caller's opts.attach_mappings after the picker's own, so both apply.
---Pickers that don't pass their opts to pickers.new get nothing; call attach(map) inside them.
---@param picker fun(opts?: table) picker function that takes telescope opts
---@param attach? fun(map: genja-finder.TelescopeMap) keys to add (default M.attach without options)
---@return fun(opts?: table)
function M.decorate(picker, attach)
	if not attach then
		attach = function(map) M.attach(map) end
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
