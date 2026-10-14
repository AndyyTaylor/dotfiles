-- C++ format-on-save: clang-format, then the dex include layout.
--
-- clang-format can group includes but only sorts them alphabetically, so it runs
-- with SortIncludes: Never and dex's cpp/scripts/dex_format.py does the
-- grouping / length sort / <> vs "" fixups afterwards. dex_pre runs first so
-- blank lines before a "}" survive clang-format (see the script's docstring). The script is found by
-- walking up from the file, so other C++ projects just get clang-format.
local SCRIPT = "scripts/dex_format.py"

local function find_script(filename)
  for dir in vim.fs.parents(filename) do
    local path = dir .. "/" .. SCRIPT
    if vim.uv.fs_stat(path) then
      return path
    end
  end
end

return {
  {
    "stevearc/conform.nvim",
    opts = function(_, opts)
      opts.formatters = opts.formatters or {}
      local condition = function(_, ctx)
        return find_script(ctx.filename) ~= nil
      end
      opts.formatters.dex_pre = {
        command = "python3",
        args = function(_, ctx)
          return { find_script(ctx.filename), "--pre", ctx.filename }
        end,
        stdin = true,
        condition = condition,
      }
      opts.formatters.dex_includes = {
        command = "python3",
        args = function(_, ctx)
          return { find_script(ctx.filename), ctx.filename }
        end,
        stdin = true,
        condition = condition,
      }

      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.cpp = { "dex_pre", "clang_format", "dex_includes" }
      opts.formatters_by_ft.c = { "dex_pre", "clang_format", "dex_includes" }
    end,
  },
}
