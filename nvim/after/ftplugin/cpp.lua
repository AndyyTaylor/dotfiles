-- dex/cpp/.clang-format sets IndentWidth: 4, but LazyVim's global default is
-- shiftwidth=2, so C++ buffers were indenting at 2. Measured against the tree:
-- cpp/**/*.cc indents in multiples of 4. (Python already gets 4 from Neovim's
-- built-in python ftplugin; ui/**/*.tsx is genuinely 2, so both are left alone.)
vim.bo.shiftwidth = 4
vim.bo.softtabstop = 4
vim.bo.tabstop = 4
vim.bo.expandtab = true
