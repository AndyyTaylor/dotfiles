-- Port of the VSCode theme "Catppuccin Mocha Darker" (siris01.catppuccin-theme).
--
-- Two separate things had to be matched:
--
--  1. Backgrounds. The Darker variant is stock Mocha with every background flattened
--     to #010101, so base/mantle/crust are overridden below.
--
--  2. Syntax colours. This is where catppuccin/nvim and the VSCode extension diverge
--     badly -- they are different ports with different scope->colour mappings. In
--     VSCode functions are yellow, keywords peach, numbers mauve and operators pink;
--     catppuccin/nvim defaults those to blue, mauve, peach and sky respectively. The
--     custom_highlights table below is transcribed from the extension's tokenColors
--     so the two actually look alike.
--
-- The theme sets "semanticHighlighting": true but only customises parameter.label,
-- so VSCode themes semantic tokens through the same tokenColors. In Neovim the LSP
-- semantic tokens (@lsp.type.*) would otherwise win over treesitter captures, so
-- both sets are assigned the same colours here.
--
-- Colours below are the literal values from catppuccin-mocha-darker.json. The two
-- alpha'd ones are pre-blended over the #010101 background, since terminal
-- highlights have no alpha channel:
--   comment            #74c7ec80 -> #3b6477
--   punctuation.sep    #cdd6f4b3 -> #9097ac
--   tag delimiters     #89dceb80 -> #456f77
return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    -- Colorscheme convention: load eagerly and first, so the palette (with the
    -- color_overrides below) is registered before anything applies a colorscheme.
    lazy = false,
    priority = 1000,
    opts = {
      flavour = "mocha",
      -- Catppuccin italicises comments and conditionals by default, which reads like
      -- a different token class (e.g. class names). Stripped on request -- note the
      -- VSCode theme does italicise comments, so this is a deliberate divergence.
      no_italic = true,
      color_overrides = {
        mocha = {
          base = "#010101",
          mantle = "#010101",
          crust = "#010101",
        },
      },
      integrations = {
        blink_cmp = true,
        gitsigns = true,
        mason = true,
        native_lsp = { enabled = true },
        neotree = true,
        snacks = true,
        treesitter = true,
        which_key = true,
      },
      custom_highlights = function()
        local vs = {
          text = "#cdd6f4",
          sky = "#89dceb",
          blue = "#89b4fa",
          peach = "#fab387",
          yellow = "#f9e2af",
          green = "#a6e3a1",
          teal = "#94e2d5",
          mauve = "#cba6f7",
          pink = "#f5c2e7",
          red = "#f38ba8",
          rosewater = "#f5e0dc",
          comment = "#3b6477",
          punct = "#9097ac",
          tagdelim = "#456f77",
        }

        local hl = {
          -- comment  <- "comment"
          Comment = { fg = vs.comment },
          ["@comment"] = { fg = vs.comment },
          ["@comment.documentation"] = { fg = vs.comment },

          -- string  <- "string", "string.regexp | constant.character | constant.other"
          String = { fg = vs.green },
          ["@string"] = { fg = vs.green },
          ["@string.regexp"] = { fg = vs.teal },
          ["@string.escape"] = { fg = vs.teal },
          ["@string.special"] = { fg = vs.teal },
          ["@character"] = { fg = vs.teal },
          Character = { fg = vs.teal },

          -- numbers / language constants  <- "constant.numeric", "constant.language"
          Number = { fg = vs.mauve },
          Float = { fg = vs.mauve },
          Boolean = { fg = vs.mauve },
          ["@number"] = { fg = vs.mauve },
          ["@number.float"] = { fg = vs.mauve },
          ["@boolean"] = { fg = vs.mauve },
          ["@constant.builtin"] = { fg = vs.mauve },

          -- variables  <- "variable", "variable.language"
          -- Members/properties are red in the VSCode theme ("variable.member"), but
          -- are kept the same as plain variables here on request -- a deliberate
          -- divergence, like no_italic above.
          Identifier = { fg = vs.text },
          ["@variable"] = { fg = vs.text },
          ["@variable.member"] = { fg = vs.text },
          ["@property"] = { fg = vs.text },
          ["@field"] = { fg = vs.text },
          ["@variable.builtin"] = { fg = vs.sky },
          -- "variable.parameter | meta.parameter"
          ["@variable.parameter"] = { fg = vs.mauve },

          -- functions  <- "entity.name.function", "variable.function", "support.function"
          Function = { fg = vs.yellow },
          ["@function"] = { fg = vs.yellow },
          ["@function.call"] = { fg = vs.yellow },
          ["@function.method"] = { fg = vs.yellow },
          ["@function.method.call"] = { fg = vs.yellow },
          ["@function.builtin"] = { fg = vs.red },
          ["@function.macro"] = { fg = vs.red },
          PreProc = { fg = vs.peach },
          ["@constructor"] = { fg = vs.blue },

          -- keywords / storage  <- "keyword", "storage", "storage.type.function"
          Keyword = { fg = vs.peach },
          Statement = { fg = vs.peach },
          Conditional = { fg = vs.peach },
          Repeat = { fg = vs.peach },
          Label = { fg = vs.peach },
          Exception = { fg = vs.peach },
          StorageClass = { fg = vs.peach },
          ["@keyword"] = { fg = vs.peach },
          ["@keyword.function"] = { fg = vs.peach },
          ["@keyword.return"] = { fg = vs.peach },
          ["@keyword.conditional"] = { fg = vs.peach },
          ["@keyword.repeat"] = { fg = vs.peach },
          ["@keyword.import"] = { fg = vs.peach },
          ["@keyword.exception"] = { fg = vs.peach },
          ["@keyword.modifier"] = { fg = vs.peach },
          ["@keyword.type"] = { fg = vs.peach },
          ["@keyword.coroutine"] = { fg = vs.peach },
          -- "keyword.operator"
          ["@keyword.operator"] = { fg = vs.pink },
          Operator = { fg = vs.pink },
          ["@operator"] = { fg = vs.pink },

          -- types. In the VSCode C++ grammar primitives are storage.type.* which
          -- falls through to the "storage" rule (peach), while user-defined types are
          -- entity.name.type -> "entity.name" (blue) and library types are
          -- support.type (sky).
          Type = { fg = vs.blue },
          ["@type"] = { fg = vs.blue },
          ["@type.definition"] = { fg = vs.blue },
          ["@type.builtin"] = { fg = vs.peach },
          ["@type.qualifier"] = { fg = vs.peach },
          ["@module"] = { fg = vs.blue },
          ["@attribute"] = { fg = vs.rosewater },

          -- punctuation  <- "punctuation.separator | punctuation.terminator"
          Delimiter = { fg = vs.punct },
          ["@punctuation.delimiter"] = { fg = vs.punct },
          ["@punctuation.bracket"] = { fg = vs.text },
          ["@punctuation.special"] = { fg = vs.peach },

          -- flash.nvim (the `s` two-char jump): the label is the key you press to
          -- land on a match -- plain bold red on the normal background (pill
          -- variants tried and rejected as hard to read)
          FlashLabel = { fg = vs.red, bold = true },

          -- markup / JSX  <- "entity.name.tag", "entity.other.attribute-name"
          ["@tag"] = { fg = vs.sky },
          ["@tag.builtin"] = { fg = vs.sky },
          ["@tag.attribute"] = { fg = vs.yellow },
          ["@tag.delimiter"] = { fg = vs.tagdelim },
        }

        -- LSP semantic tokens win over treesitter, so mirror the same colours onto
        -- the @lsp.type.* groups clangd/basedpyright/vtsls emit.
        local lsp = {
          class = vs.blue,
          struct = vs.blue,
          enum = vs.blue,
          interface = vs.blue,
          type = vs.blue,
          typeParameter = vs.blue,
          concept = vs.blue,
          namespace = vs.blue,
          ["function"] = vs.yellow,
          method = vs.yellow,
          macro = vs.red,
          parameter = vs.mauve,
          property = vs.text, -- members match plain variables (see note above)
          variable = vs.text,
          enumMember = vs.text,
          keyword = vs.peach,
          modifier = vs.peach,
          number = vs.mauve,
          string = vs.green,
          operator = vs.pink,
          comment = vs.comment,
          decorator = vs.rosewater,
        }
        for token, colour in pairs(lsp) do
          hl["@lsp.type." .. token] = { fg = colour }
        end

        return hl
      end,
    },
  },
  {
    "LazyVim/LazyVim",
    -- NOT "catppuccin": Neovim 0.12 bundles its own /usr/share/nvim/runtime/colors/
    -- catppuccin.vim, which shadows the plugin's colors/catppuccin.lua and hardcodes
    -- stock Mocha (guibg=#1e1e2e), ignoring color_overrides entirely. The plugin's
    -- flavour-specific name has no such collision in the Neovim runtime.
    opts = { colorscheme = "catppuccin-mocha" },
  },
}
