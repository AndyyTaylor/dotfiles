-- Tab accepts the completion.
--
-- LazyVim defaults blink.cmp to the "enter" preset (Enter accepts). The "super-tab"
-- preset maps <Tab> to select_and_accept and deliberately leaves <CR> unmapped, so
-- Enter just inserts a newline -- matching "editor.acceptSuggestionOnEnter": "off"
-- in the VSCode settings.
--
-- When the completion menu is closed, <Tab> falls through to snippet_forward and
-- then to a literal Tab, so normal indenting still works.
return {
  {
    "saghen/blink.cmp",
    opts = {
      keymap = { preset = "super-tab" },
      -- No inline preview of the selected item. blink defaults this off; it is on
      -- here only because LazyVim sets vim.g.ai_cmp, which exists for AI sources
      -- previewing inline but also applies to ordinary LSP completions.
      completion = { ghost_text = { enabled = false } },
    },
  },
}
