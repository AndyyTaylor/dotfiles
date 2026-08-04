-- Python LSP: basedpyright (types/hover/definitions) + ruff (lint, organise imports).
--
-- Both are pinned to uv-installed binaries with `mason = false`, like clangd:
--   uv tool install basedpyright   # PyPI build, bundles its own node runtime
--   uv tool install ruff
-- Mason's basedpyright is the npm package and would need node on PATH, which is
-- deliberately kept repo-local here (~/.local/dex-node), so the PyPI build is the
-- one that works without a system node.
--
-- before_init fills in per-project paths, because they're only known once a root
-- directory is resolved:
--   * pythonPath -> <root>/.venv/bin/python, so imports resolve against the
--     project's own venv (torch, numpy, ...) instead of the system interpreter
--   * extraPaths -> source roots that are on sys.path at runtime but aren't the
--     project root. dex runs its python from py/, so `from nn.dex import Dex`
--     only resolves with py/ on the path.
local SOURCE_DIRS = { "py", "src" }

local function project_paths(root)
  local paths = { extra = {} }

  local venv_python = root .. "/.venv/bin/python"
  if vim.uv.fs_stat(venv_python) then
    paths.python = venv_python
  end

  for _, dir in ipairs(SOURCE_DIRS) do
    local abs = root .. "/" .. dir
    if vim.uv.fs_stat(abs) then
      table.insert(paths.extra, abs)
    end
  end

  return paths
end

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          mason = false,
          cmd = { "basedpyright-langserver", "--stdio" },
          before_init = function(_, config)
            local paths = project_paths(config.root_dir or vim.fn.getcwd())
            local settings = config.settings or {}
            settings.python = vim.tbl_deep_extend("force", settings.python or {}, {
              pythonPath = paths.python,
              analysis = { extraPaths = paths.extra },
            })
            config.settings = settings
          end,
          settings = {
            basedpyright = {
              analysis = {
                -- No type diagnostics at all. Python's optional typing plus loose
                -- library stubs (torch.onnx.export returning ONNXProgram | None,
                -- tensors indexed with numpy bool arrays) means the useful signal
                -- is buried in complaints about things that are fine at runtime.
                -- Everything else the server does -- hover, completion, go to
                -- definition, references, unresolved-import errors -- is unaffected,
                -- and ruff still reports real bugs like undefined names.
                typeCheckingMode = "off",
                diagnosticMode = "openFilesOnly",
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
              },
            },
          },
        },
        ruff = {
          mason = false,
          cmd = { "ruff", "server" },
        },
      },
    },
  },
}
