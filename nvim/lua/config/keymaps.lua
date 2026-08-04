-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Left terminal column (see lua/config/sideterm.lua).
-- <leader>t is free in this setup; note LazyVim's optional test extra also wants that
-- prefix, so remap these if you ever enable it.
local sideterm = require("config.sideterm")
sideterm.setup()

vim.keymap.set("n", "<leader>tt", sideterm.toggle, { desc = "Terminal column (toggle)" })
vim.keymap.set("n", "<leader>ta", function()
  sideterm.focus("agents")
end, { desc = "Terminal: claude agents" })
vim.keymap.set("n", "<leader>ts", function()
  sideterm.focus("shell")
end, { desc = "Terminal: shell" })
vim.keymap.set("n", "<leader>tn", sideterm.add, { desc = "Terminal: new pane in column" })

-- Ctrl-h from the editor goes to the *last-focused* terminal pane, not the one
-- nearest the cursor row (which is what plain <C-w>h picks). Everywhere else it
-- behaves exactly like LazyVim's default left-window motion.
vim.keymap.set("n", "<C-h>", sideterm.smart_left, { desc = "Go to Left Window" })

-- ---------------------------------------------------------------------------
-- Window navigation out of a terminal pane.
--
-- LazyVim only binds <C-h/j/k/l> in normal mode, so inside a terminal (insert mode)
-- those keystrokes are forwarded to the running program -- which is why the cursor
-- gets stuck in the `claude agents` pane. These leave terminal mode first
-- (<C-\><C-n>) and then move, so the keys behave the same everywhere.
--
-- Trade-off: the terminal program no longer receives Ctrl-h/j/k/l -- notably Ctrl-l
-- (clear screen) in the shell pane. Neovim has no built-in literal-key prefix in
-- terminal mode, so <C-v> is defined below to supply one: <C-v><C-l> sends a real
-- Ctrl-l to the program. (Ctrl-h is ASCII backspace, but the Backspace key itself
-- sends DEL 0x7f, so ordinary backspacing is unaffected.)
-- ---------------------------------------------------------------------------
local directions = { h = "Left", j = "Lower", k = "Upper", l = "Right" }
for key, label in pairs(directions) do
  vim.keymap.set(
    "t",
    "<C-" .. key .. ">",
    "<C-\\><C-n><C-w>" .. key,
    { desc = "Go to " .. label .. " Window" }
  )
end

-- ---------------------------------------------------------------------------
-- <S-CR> / <C-CR> in a terminal: insert a newline instead of submitting.
--
-- Neovim's terminal emulator encodes both Enter and Shift-Enter as a bare CR, so
-- a CLI reading the pty cannot tell them apart -- pressing Shift-Enter in the
-- claude pane submitted the prompt instead of opening a new line.
--
-- ESC CR is the sequence claude's own `/terminal-setup` installs into VS Code,
-- Alacritty and Zed for exactly this, and its input parser reads `\r` and
-- `\x1B\r` as return with meta set. Sending it verbatim gets the same result
-- without touching the outer terminal's config. Verified with `cat`: the job
-- receives 1b 0a with this map versus a bare 0a without it.
--
-- Requires the outer terminal to report Shift-Enter distinctly (kitty keyboard
-- protocol -- foot does). Where it doesn't, claude's own fallbacks still work:
-- Alt-Enter, or a trailing backslash before Enter.
-- ---------------------------------------------------------------------------
for _, lhs in ipairs({ "<S-CR>", "<C-CR>" }) do
  vim.keymap.set("t", lhs, function()
    local job = vim.b.terminal_job_id
    if job then
      vim.api.nvim_chan_send(job, "\27\r")
    end
  end, { desc = "Terminal: newline (meta-return)" })
end

-- Literal-key escape hatch: read the next keypress raw and write it straight to the
-- terminal job, bypassing the mappings above.
vim.keymap.set("t", "<C-v>", function()
  local ok, key = pcall(vim.fn.getcharstr)
  local job = vim.b.terminal_job_id
  if ok and job and key ~= "" then
    vim.api.nvim_chan_send(job, key)
  end
end, { desc = "Terminal: send next key literally" })

-- ---------------------------------------------------------------------------
-- <C-Tab> : VSCode-style recently-viewed file switcher.
--
-- Opens the open-buffer list sorted by last use, with the previously viewed file
-- at the top -- so <C-Tab><CR> flips to the last file, and repeated <C-Tab>
-- cycles further down the list before <CR> opens the selection. Terminals only
-- report key presses, not releases, so VSCode's "release Ctrl to open" cannot be
-- reproduced; <CR> confirms instead.
--
-- Needs a terminal that distinguishes Ctrl+Tab from Tab (kitty keyboard
-- protocol); in one that doesn't, this mapping simply never fires.
-- ---------------------------------------------------------------------------
vim.keymap.set("n", "<C-Tab>", function()
  Snacks.picker.buffers({
    current = false, -- exclude the file you're in; top item = previous file
    sort_lastused = true,
    win = {
      input = {
        keys = {
          ["<C-Tab>"] = { "list_down", mode = { "i", "n" } },
          ["<C-S-Tab>"] = { "list_up", mode = { "i", "n" } },
        },
      },
    },
  })
end, { desc = "Recent Buffers (MRU)" })

-- ---------------------------------------------------------------------------
-- <leader>' : switch between header and source.
--
-- Same action as LazyVim's <leader>ch from the clangd extra. Guarded because the
-- command only exists once clangd has attached, so pressing it in a Python or TS
-- buffer gives a useful message instead of "not an editor command".
-- ---------------------------------------------------------------------------
vim.keymap.set("n", "<leader>'", function()
  if vim.fn.exists(":LspClangdSwitchSourceHeader") == 2 then
    vim.cmd("LspClangdSwitchSourceHeader")
  else
    vim.notify("clangd is not attached to this buffer", vim.log.levels.WARN)
  end
end, { desc = "Switch Source/Header (C/C++)" })

-- ---------------------------------------------------------------------------
-- Swap <leader>f and <leader><leader>.
--
--   before:  <leader><leader> = Find Files      <leader>f = "file/find" prefix
--   after:   <leader>f        = Find Files      <leader><leader> = the prefix
--
-- <leader>f must stop being a prefix, otherwise every <leader>f? binding would sit
-- behind 'timeoutlen' while Neovim waits to see whether another key follows.
--
-- This is done at runtime rather than by patching plugin specs because the bindings
-- come from three separate places: the snacks picker spec (ff fF fb fB fc fg fr fR
-- fp), the snacks explorer spec (fe fE), and LazyVim's own config/keymaps.lua (fn ft
-- fT). snacks is eager (lazy=false), so by the time this file runs they are all real
-- mappings with real callbacks rather than lazy-load stubs.
--
-- Neovim reports lhs with <leader> already expanded, hence the literal " " (space)
-- prefixes below.
-- ---------------------------------------------------------------------------
local LEADER_F = " f"
local LEADER_LEADER = "  "

local function opts_of(m)
  return {
    desc = m.desc,
    silent = m.silent == 1,
    expr = m.expr == 1,
    nowait = m.nowait == 1,
    remap = m.noremap ~= 1,
  }
end

-- Reuse the exact Find Files action that currently sits on <leader><leader>, so the
-- new <leader>f behaves identically (root-dir aware) rather than being reimplemented.
local root_map = vim.fn.maparg("<leader><leader>", "n", false, true)
local find_files = root_map and root_map.callback

-- 1. move every <leader>f? to <leader><leader>?
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if #m.lhs > 2 and m.lhs:sub(1, 2) == LEADER_F then
    vim.keymap.set("n", LEADER_LEADER .. m.lhs:sub(3), m.callback or m.rhs, opts_of(m))
    pcall(vim.keymap.del, "n", m.lhs)
  end
end

-- 2. repoint anything that mapped *into* a <leader>f? key. LazyVim defines
--    <leader>e / <leader>E as remap=true onto <leader>fe / <leader>fE, so without
--    this the explorer keys would break silently.
for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
  if type(m.rhs) == "string" and #m.rhs > 2 and m.rhs:sub(1, 2) == LEADER_F then
    vim.keymap.set("n", m.lhs, LEADER_LEADER .. m.rhs:sub(3), opts_of(m))
  end
end

-- 3. <leader><leader> is a prefix now, so drop its direct binding and hand Find Files
--    to <leader>f.
pcall(vim.keymap.del, "n", "<leader><leader>")
if find_files then
  vim.keymap.set("n", "<leader>f", find_files, { desc = "Find Files (Root Dir)" })
end

-- ---------------------------------------------------------------------------
-- Diagnostics / explorer rearrangement:
--
--   <leader>e  next LSP error         (was explorer; ]e/[e and ]d/[d still work)
--   <leader>n  file explorer          (was notification history, now unbound --
--                                      recent notifications remain reachable via
--                                      :messages and snacks' <leader>un dismiss)
--
-- Overwriting <leader>n IS the unbind of notification history; no separate del
-- needed. <leader>E (explorer in cwd) is left where it was.
-- ---------------------------------------------------------------------------
vim.keymap.set("n", "<leader>e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR, float = true })
end, { desc = "Next Error" })
vim.keymap.set("n", "<leader>n", function()
  Snacks.explorer({ cwd = LazyVim.root() })
end, { desc = "Explorer (Root Dir)" })
