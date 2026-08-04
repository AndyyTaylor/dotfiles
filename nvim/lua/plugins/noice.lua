-- Silence the "✔ basedpyright" progress banners in the bottom-right corner.
--
-- noice renders every LSP $/progress message in its "mini" view; basedpyright
-- reports one per analysis pass, so editing python flashes a banner constantly.
-- clangd's are kept: indexing a C++ tree takes minutes and the progress is the
-- only sign it is still working.
local QUIET_CLIENTS = { basedpyright = true, ruff = true }

return {
  {
    "folke/noice.nvim",
    -- function form: append to LazyVim's routes rather than replacing them
    opts = function(_, opts)
      opts.routes = opts.routes or {}
      table.insert(opts.routes, {
        filter = {
          event = "lsp",
          kind = "progress",
          cond = function(message)
            local client = vim.tbl_get(message.opts or {}, "progress", "client")
            return QUIET_CLIENTS[client] == true
          end,
        },
        opts = { skip = true },
      })
    end,
  },
}
