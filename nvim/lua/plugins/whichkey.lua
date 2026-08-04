-- which-key labels for the <leader>f / <leader><leader> swap done in
-- lua/config/keymaps.lua. LazyVim registers { "<leader>f", group = "file/find" } in
-- its editor.lua spec; which-key has opts_extend = { "spec" }, so these entries are
-- appended and the later <leader>f entry wins over that stale group label.
return {
  {
    "folke/which-key.nvim",
    opts = {
      spec = {
        { "<leader><leader>", group = "file/find" },
        { "<leader>f", desc = "Find Files (Root Dir)" },
        { "<leader>'", desc = "Switch Source/Header (C/C++)" },
        { "<leader>t", group = "terminal" },
      },
    },
  },
}
