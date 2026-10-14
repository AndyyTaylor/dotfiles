-- Turn off inlay hints: the virtual-text parameter-name and inferred-type labels
-- that LazyVim enables by default. Matches "editor.inlayHints.enabled": "off" in
-- the VSCode settings.
--
-- Note this is separate from clangd's --function-arg-placeholders=0 (set in
-- clangd.lua), which controls completion snippet placeholders, not these labels.
--
-- File watching is turned on for every server. Neovim leaves
-- didChangeWatchedFiles off on Linux by default, so servers never heard about
-- files created (or deleted) after they started: basedpyright couldn't resolve
-- a module added mid-session (go to definition just did nothing) until
-- :LspRestart. On Linux nvim watches with inotifywait, which needs
-- inotify-tools installed.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      inlay_hints = { enabled = false },
      servers = {
        ["*"] = {
          capabilities = {
            workspace = { didChangeWatchedFiles = { dynamicRegistration = true } },
          },
        },
      },
    },
  },
}
