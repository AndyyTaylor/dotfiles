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

-- comment leaders the patterns anchor on. a leader counts at the start of a line
-- or after whitespace, so trailing comments (`x = 1;  // todo`) match too
local leader = [[%(\/\/|#|--|;|\/\*|\*)\s*]]
local after_space = [[%(^|\s)]]

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
      -- fg-only, from the comment leader to end of line. the leader is part of
      -- each pattern's outer capture, so it's coloured as the "keyword"; `before`
      -- stays off, since on a trailing comment it would colour the code too
      before = "",
      keyword = "fg",
      after = "fg",
      comments_only = true,
      -- a keyword line otherwise bleeds into any following comment line
      multiline = false,
      pattern = {
        -- word keywords, colon optional, only at the start of a comment. the
        -- outer capture is what gets highlighted, the inner one names the keyword
        after_space .. [[(]] .. leader .. [[(KEYWORDS))>]],
        -- classic `TODO:` anywhere in a comment: whole comment on its own line,
        -- from the keyword on in a trailing one (an unanchored leader would also
        -- match `;` / `*` in code first)
        [[^\s*(]] .. leader .. [[.{-}<(KEYWORDS))\s*:]],
        [[<(KEYWORDS)\s*:]],
        -- symbol keywords: the inner capture is the symbol, mapped to its keyword
        -- name via the __index below
        after_space .. [[(]] .. leader .. [[(\?))]],
        after_space .. [[(]] .. leader .. [[(\*))]],
        after_space .. [[(]] .. leader .. [[(!))]],
      },
    },
    search = {
      -- KEYWORDS never contains the symbols, so match those explicitly
      pattern = [=[\b(KEYWORDS)\b|(^|\s)(//|#|--|;|/\*|\*)\s*[?*!]]=],
    },
  },
  config = function(_, opts)
    require("todo-comments").setup(opts)
    setmetatable(require("todo-comments.config").keywords, {
      __index = { ["?"] = "QUESTION", ["*"] = "STAR", ["!"] = "ALERT" },
    })
  end,
}
