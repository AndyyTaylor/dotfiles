-- Close any snacks picker (Find Files, grep, buffers, ...) with a single Esc.
--
-- By default the picker's input window is a real vim buffer: the first Esc only
-- leaves insert mode (so you could use normal-mode motions inside the search
-- field) and a second Esc closes the window. Nobody here edits the query with
-- vim motions, so bind Esc to close in both modes. `<C-c>` still cancels too.
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        win = {
          input = {
            keys = {
              ["<Esc>"] = { "close", mode = { "n", "i" } },
            },
          },
        },
      },
    },
  },
}
