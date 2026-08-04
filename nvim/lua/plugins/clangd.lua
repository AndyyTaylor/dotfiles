-- C++ LSP for the dex cpp/ tree.
--
-- Pinned to the system clangd (/usr/bin/clangd, currently 22.1.8) rather than a
-- Mason-managed one: the system binary's resource-dir is /usr/lib/clang/22, which
-- matches the libstdc++ the C++23 build actually compiles against. A Mason clangd
-- ships its own resource dir and mismatches those headers.
--
-- No --compile-commands-dir is passed on purpose. clangd walks up from the source
-- file and checks each ancestor plus its build/ subdir, so it finds
-- cpp/build/compile_commands.json no matter which directory nvim was launched from.
-- A relative --compile-commands-dir=build (as used in the VSCode settings) resolves
-- against the process cwd instead, and breaks when nvim starts at the repo root.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = {
          mason = false,
          cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--completion-style=detailed",
            "--header-insertion=never",
            -- matches "--function-arg-placeholders=0" from the VSCode clangd config
            "--function-arg-placeholders=0",
            "--pch-storage=memory",
          },
        },
      },
    },
  },
}
