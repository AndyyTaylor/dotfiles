return {
  -- Drop the clock from the right end of the statusline; sway's bar already shows the time.
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.sections.lualine_z = {}
    end,
  },

  -- No smooth-scroll animation: gg / G / <C-d> jump instantly.
  {
    "folke/snacks.nvim",
    opts = { scroll = { enabled = false } },
  },
}
