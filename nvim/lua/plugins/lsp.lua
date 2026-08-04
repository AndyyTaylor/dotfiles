-- Turn off inlay hints: the virtual-text parameter-name and inferred-type labels
-- that LazyVim enables by default. Matches "editor.inlayHints.enabled": "off" in
-- the VSCode settings.
--
-- Note this is separate from clangd's --function-arg-placeholders=0 (set in
-- clangd.lua), which controls completion snippet placeholders, not these labels.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
    },
  },
}
