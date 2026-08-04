-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- ---------------------------------------------------------------------------
-- Auto-insert on entering a terminal window.
--
-- Without this, moving into a terminal pane (e.g. <C-h> from the editor) lands in
-- terminal-normal mode and you have to press `i` before typing.
--
-- Scrolling still works: <C-\><C-n> inside a terminal fires neither BufEnter nor
-- WinEnter, so you stay in normal mode to scroll or copy. Insert mode is only forced
-- when the window is actually entered from elsewhere.
-- ---------------------------------------------------------------------------
vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "TermOpen" }, {
  group = vim.api.nvim_create_augroup("user_term_insert", { clear = true }),
  desc = "Enter insert mode when moving into a terminal window",
  callback = function()
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].buftype ~= "terminal" then
      return
    end
    -- Skip terminals whose job has exited: they show "[Process exited]" and any
    -- keypress closes the window, so dropping into insert there is a footgun.
    local job = vim.b[buf].terminal_job_id
    if not job or vim.fn.jobwait({ job }, 0)[1] ~= -1 then
      return
    end
    -- Deferred with a re-check, because `startinsert` only takes effect once the
    -- autocmd returns. Something that opens a terminal and then moves focus
    -- elsewhere (sideterm.open() does exactly this) would otherwise strand the
    -- editor in insert mode.
    vim.schedule(function()
      if vim.api.nvim_get_current_buf() == buf and vim.bo[buf].buftype == "terminal" then
        vim.cmd("startinsert")
      end
    end)
  end,
})

-- ---------------------------------------------------------------------------
-- Open the sideterm column and the file explorer at startup.
--
-- Only when nvim is opened as "the IDE" -- no args (`nvim`) or a single directory
-- arg (`nvim .`, `nvim ~/dex`). Editing a specific file (git commit messages,
-- quick one-off edits) skips both, so no `claude agents` process is spawned there.
--
-- This file loads on VeryLazy, which fires *after* VimEnter, so the usual VimEnter
-- autocmd would never run -- hence the vim_did_enter branch.
-- ---------------------------------------------------------------------------
local function open_workspace_ui()
  require("config.sideterm").open()
  -- focus=false: the explorer window opens but the cursor stays in the editor.
  Snacks.explorer({ focus = false })
end

local argc = vim.fn.argc()
if argc == 0 or (argc == 1 and vim.fn.isdirectory(vim.fn.argv(0)) == 1) then
  if vim.v.vim_did_enter == 1 then
    vim.schedule(open_workspace_ui)
  else
    vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = open_workspace_ui })
  end
end

-- ---------------------------------------------------------------------------
-- Autosave -- mirrors VSCode's files.autoSave = "afterDelay" / autoSaveDelay 200.
--
-- The write uses `noautocmd`, which skips BufWritePre and therefore skips
-- LazyVim's format-on-save. That is deliberate and matches VSCode: it does not
-- run formatOnSave for afterDelay autosaves, only for explicit saves. Pressing
-- <C-s> / :w still formats as normal.
-- ---------------------------------------------------------------------------
local AUTOSAVE_DELAY_MS = 200

local group = vim.api.nvim_create_augroup("user_autosave", { clear = true })
local timer = assert((vim.uv or vim.loop).new_timer())

local function should_save(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local bo = vim.bo[buf]
  -- Only real, on-disk, editable files: skips terminals, help, quickfix and
  -- scratch buffers, plus anything read-only or unmodified.
  if bo.buftype ~= "" or not bo.modifiable or bo.readonly or not bo.modified then
    return false
  end
  if bo.filetype == "gitcommit" or bo.filetype == "gitrebase" then
    return false
  end
  return vim.api.nvim_buf_get_name(buf) ~= ""
end

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave" }, {
  group = group,
  desc = "Autosave after a short idle delay",
  callback = function(ev)
    local buf = ev.buf
    timer:stop()
    timer:start(
      AUTOSAVE_DELAY_MS,
      0,
      vim.schedule_wrap(function()
        if should_save(buf) then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("silent! noautocmd write")
          end)
        end
      end)
    )
  end,
})
