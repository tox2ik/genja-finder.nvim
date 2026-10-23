
-- genja-finder: live grep (rg/ack/grep) and live find (fd/rg --files) telescope pickers
-- with a shared scope: root (<M-r>), skip set (<M-i>), grep <-> find switch (<F1>),
-- command popup (<M-c>), next command (<M-C>), preview toggle (<C-p>). See :help genja-finder.
-- Also for any picker: attach_shared_keys(map) and enhance(picker) add Telemap's keys and the <M-f> filter.

---setup() options: the shared scan options, plus per-picker defaults.
---@class genja-finder.Opts : genja-finder.ScanOpts
---@field grep? genja-finder.GrepOpts  live grep only (binary, separator, min_chars, filters, ...)
---@field find? genja-finder.FindOpts  live find only (binary, follow)

local M = {}

---Merge `opts` into the defaults. Optional: the pickers work without it.
---@param opts? genja-finder.Opts
function M.setup(opts)
	opts = vim.deepcopy(opts or {})
	local scope = require 'genja-finder.scope'
	local grep = require 'genja-finder.grep'
	local find = require 'genja-finder.find'

	grep.defaults = vim.tbl_extend('force', grep.defaults, opts.grep or {})
	find.defaults = vim.tbl_extend('force', find.defaults, opts.find or {})
	opts.grep, opts.find = nil, nil
	scope.defaults = vim.tbl_extend('force', scope.defaults, opts)
end

---Live grep: text search, rg/ack/grep rerun on each keystroke.
---@param opts? genja-finder.GrepOpts
function M.live_grep(opts) require('genja-finder.grep').live_grep(opts) end

---Live find: fuzzy match over the file list from fd / rg --files.
---@param opts? genja-finder.FindOpts
function M.live_find(opts) require('genja-finder.find').live_find(opts) end

---Shared keys for any picker's attach_mappings: Telemap (<esc>, <F2>/<F3>) and refine (<M-f>).
---@param map genja-finder.TelescopeMap
function M.attach_shared_keys(map)
	require('genja-finder.telemap').Telemap(map)
	require('genja-finder.refine').attach(map)
end

---Wrap a picker function so it opens with M.attach_shared_keys's keys, e.g. enhance(builtin.oldfiles).
---Works for pickers that pass their opts to pickers.new; others call M.attach_shared_keys(map) themselves.
---@param picker fun(opts?: table)
---@return fun(opts?: table)
function M.enhance(picker)
	return require('genja-finder.refine').decorate(picker, M.attach_shared_keys)
end

return M
