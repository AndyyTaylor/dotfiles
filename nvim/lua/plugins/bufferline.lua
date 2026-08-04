-- Keep the buffer tabs over the editor only, not over the sideterm column.
--
-- The tabline is global and always spans the full screen width, so bufferline
-- can't literally be attached to one window; its "offsets" feature instead blanks
-- the tabline over edge windows whose filetype matches. sideterm.lua stamps its
-- terminal buffers with filetype=sideterm for this. Bufferline inspects the top
-- window of an edge column, i.e. the claude-agents pane.
--
-- opts is a function so the offset is appended to LazyVim's defaults (neo-tree
-- etc.) -- a plain opts table would index-merge the offsets lists.
return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.offsets = opts.options.offsets or {}
      table.insert(opts.options.offsets, { filetype = "sideterm" })
    end,
  },
}
