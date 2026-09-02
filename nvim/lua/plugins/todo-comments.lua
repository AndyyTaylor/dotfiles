-- Better Comments (VSCode) style comment highlighting on top of todo-comments.
--
--   // todo ...   orange
--   // ? ...      blue
--   // * ...      orange
--   // ! ...      red
--
-- The whole comment line takes the colour, not just a badge on the keyword.
-- Colours are the Material Theme (dark) palette.
--
-- todo-comments can't take "?", "*" or "!" as keyword names directly: it splices
-- keyword names unescaped into a very-magic vim regex (and the ripgrep regex for
-- :TodoTelescope), and uses them in highlight group names (TodoFg?). So the
-- symbols get named keywords (QUESTION / STAR / ALERT) plus their own anchored
-- highlight patterns, and the symbol -> name mapping is attached to the plugin's
-- alias table via __index so the search regex builder (which uses pairs()) never
-- sees the raw symbols.
local material = {
  orange = "#F78C6C",
  blue = "#82AAFF",
  red = "#FF5370",
}

-- comment leaders the symbol patterns anchor on
local leader = [[^\s*%(\/\/|#|--|;|\/\*|\*)\s*]]

return {
  "folke/todo-comments.nvim",
  opts = {
    keywords = {
      TODO = { icon = " ", color = material.orange, alt = { "todo" } },
      QUESTION = { icon = "?", color = material.blue },
      STAR = { icon = "*", color = material.orange },
      ALERT = { icon = "!", color = material.red },
    },
    highlight = {
      -- fg-only, whole line: leading text (the comment leader), keyword, and
      -- everything after all take the keyword colour
      before = "fg",
      keyword = "fg",
      after = "fg",
      comments_only = true,
      -- a keyword line otherwise bleeds into any following comment line
      multiline = false,
      pattern = {
        -- word keywords, colon optional, only at the start of a comment
        leader .. [[(KEYWORDS)>]],
        -- classic `TODO:` anywhere in a comment
        [[.*<(KEYWORDS)\s*:]],
        -- symbol keywords: the capture is the symbol, mapped to its keyword
        -- name via the __index below
        leader .. [[(\?)]],
        leader .. [[(\*)]],
        leader .. [[(!)]],
      },
    },
    search = {
      -- KEYWORDS never contains the symbols, so match those explicitly
      pattern = [=[\b(KEYWORDS)\b|^\s*(//|#|--|;|/\*|\*)\s*[?*!]]=],
    },
  },
  config = function(_, opts)
    require("todo-comments").setup(opts)
    setmetatable(require("todo-comments.config").keywords, {
      __index = { ["?"] = "QUESTION", ["*"] = "STAR", ["!"] = "ALERT" },
    })
  end,
}
