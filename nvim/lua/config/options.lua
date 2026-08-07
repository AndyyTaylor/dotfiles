-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Touchpad side-swipes were shifting terminal panes sideways; keep vertical
-- wheel scrolling but ignore horizontal scroll events entirely.
vim.opt.mousescroll = "ver:3,hor:0"

-- LazyVim enables 'list' mode, which renders trailing spaces as "-"; drop
-- that marker while keeping the other invisible-char indicators.
vim.opt.listchars:remove("trail")
