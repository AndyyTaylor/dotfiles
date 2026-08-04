-- File explorer on the right.
--
-- LazyVim v16 uses snacks.nvim's picker for the explorer (not neo-tree). The
-- "sidebar" preset defaults to position=left; the nested `layout.layout` table is
-- how snacks expects the position override (see the comment in
-- snacks.nvim/lua/snacks/picker/config/sources.lua under M.explorer).
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            layout = { layout = { position = "right" } },
          },
        },
      },
    },
  },
}
