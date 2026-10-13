
-- genja-finder: live grep (rg/ack/grep) and live find (rg --files/fd) telescope pickers
-- with a shared scope: root (<M-r>), skip set (<M-i>), grep <-> find switch (<F1>),
-- command popup (<M-c>), preview toggle (<C-p>). See :help genja-finder.

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

---Live find: fuzzy match over the file list from rg --files / fd.
---@param opts? genja-finder.FindOpts
function M.live_find(opts) require('genja-finder.find').live_find(opts) end

return M
