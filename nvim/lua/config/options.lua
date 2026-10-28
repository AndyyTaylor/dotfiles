-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- :restart saves and restores a session. The sideterm column and the explorer
-- are reopened fresh after it (config/autocmds.lua), so keep their windows out
-- of the session: restored terminals would be stray extra shells, and the
-- explorer's window would come back as an empty split.
vim.opt.sessionoptions:remove({ "terminal", "blank" })

-- Touchpad side-swipes were shifting terminal panes sideways; keep vertical
-- wheel scrolling but ignore horizontal scroll events entirely.
vim.opt.mousescroll = "ver:3,hor:0"

-- LazyVim enables 'list' mode, which renders trailing spaces as "-"; drop
-- that marker while keeping the other invisible-char indicators.
vim.opt.listchars:remove("trail")
