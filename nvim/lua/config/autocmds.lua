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
-- Open the file explorer at startup.
--
-- Only when nvim is opened as "the IDE" -- no args (`nvim`) or a single directory
-- arg (`nvim .`, `nvim ~/dex`). Editing a specific file (git commit messages,
-- quick one-off edits) skips it.
--
-- The sideterm column (lua/config/sideterm.lua) is deliberately *not* opened here:
-- it is on-demand only, via <leader>tt / <leader>ta / <leader>ts or :SideTerm. That
-- also means `claude agents` is only spawned once the column is first opened.
--
-- This file loads on VeryLazy, which fires *after* VimEnter, so the usual VimEnter
-- autocmd would never run -- hence the vim_did_enter branch.
-- ---------------------------------------------------------------------------
local function open_workspace_ui()
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
-- The write uses `noautocmd`, which skips BufWritePre and therefore LazyVim's
-- format-on-save, so the autosave formats explicitly instead (same formatters
-- as :w, and still honours <leader>uf toggling autoformat off). Not while the
-- buffer is being edited though: code shifting around mid-edit gets in the way
-- (and reformatting mid-typing would eat e.g. the trailing space just typed).
-- The current buffer is written unformatted, and formatted once it's left --
-- another buffer or window entered, the buffer closed, or nvim quit -- so it
-- still gets formatted over a session, just not under the cursor. Buffers that
-- aren't current, like the ones an LSP rename touches, format straight away.
--
-- Every modified buffer is written, not just the one being typed in, and
-- BufModifiedSet is a trigger alongside the text events. An LSP rename edits
-- every file the symbol appears in, loading the untouched ones as hidden
-- buffers; those fire no TextChanged (that only fires for the current buffer)
-- and were left dirty, so the tree stayed broken until each file was opened by
-- hand. BufModifiedSet fires for hidden buffers too, so the rename now lands on
-- disk in full.
--
-- C++ is only formatted once clangd says it parses. Formatting a half-typed
-- statement goes wrong: with the ";" not typed yet, clang-format reads it as
-- carrying on into the next line and joins the two. Tree-sitter can't tell (its
-- error recovery accepts that as one expression), so this goes by clangd's
-- diagnostics: parse errors are the ones coded expected* (expected_semi_after_expr,
-- expected_expression, ...), and only diagnostics for the buffer's current
-- version count, since clangd lags the typing. Until then the buffer is written
-- unformatted, and formatted when diagnostics saying it parses come in.
--
-- The autosave format is part of the edit it follows as far as undo goes: one u
-- takes back both. And a buffer that's been stepped back with u isn't formatted
-- until the next edit, or the format would go straight back on.
-- ---------------------------------------------------------------------------
local AUTOSAVE_DELAY_MS = 200

local group = vim.api.nvim_create_augroup("user_autosave", { clear = true })
local timer = assert((vim.uv or vim.loop).new_timer())

-- buf -> { version = <buffer version clangd last published for>, parse_error = bool }
local clangd_parse = {}
-- bufs whose autosave format was held back for clangd
local format_pending = {}
-- current bufs autosaved unformatted, formatted once they're left
local unformatted = {}

local on_publish = vim.lsp.diagnostic.on_publish_diagnostics
vim.lsp.diagnostic.on_publish_diagnostics = function(err, params, ctx, ...)
  local client = vim.lsp.get_client_by_id(ctx.client_id)
  if client and client.name == "clangd" and params then
    local parse_error = false
    for _, d in ipairs(params.diagnostics or {}) do
      local code = type(d.code) == "string" and d.code or ""
      if d.severity == vim.lsp.protocol.DiagnosticSeverity.Error and code:find("^expected") then
        parse_error = true
        break
      end
    end
    clangd_parse[vim.uri_to_bufnr(params.uri)] = { version = params.version, parse_error = parse_error }
  end
  return on_publish(err, params, ctx, ...)
end

-- true / false once clangd has a verdict on the buffer as it is now, nil while
-- it's still catching up. Buffers without clangd always parse
local function parses(buf)
  if #vim.lsp.get_clients({ bufnr = buf, name = "clangd" }) == 0 then
    return true
  end
  local state = clangd_parse[buf]
  if not state or state.version == nil or state.version ~= vim.lsp.util.buf_versions[buf] then
    return nil
  end
  return not state.parse_error
end

local function format_buffer(buf)
  -- stepped back with u, so leave the buffer as the undo put it. formatting it
  -- would redo the format just undone, and start a new branch of undo history
  local undo = vim.fn.undotree(buf)
  if undo.seq_cur ~= undo.seq_last then
    return
  end

  -- joined onto the edit's undo step, so a single u takes back both
  pcall(vim.cmd.undojoin)
  pcall(LazyVim.format, { buf = buf })
end

local function autosave_format(buf)
  if parses(buf) then
    format_pending[buf] = nil
    format_buffer(buf)
  else
    format_pending[buf] = true
  end
end

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

local function save_dirty_buffers()
  local current = vim.api.nvim_get_current_buf()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if should_save(buf) then
      vim.api.nvim_buf_call(buf, function()
        if buf == current then
          unformatted[buf] = true
        else
          autosave_format(buf)
        end
        vim.cmd("silent! noautocmd write")
      end)
    end
  end
end

-- the format the autosave held back while the buffer was current. should_save
-- covers an edit whose autosave hasn't fired yet
local function format_left(buf)
  if not (unformatted[buf] or should_save(buf)) or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  unformatted[buf] = nil
  vim.api.nvim_buf_call(buf, function()
    autosave_format(buf)
    if should_save(buf) then
      vim.cmd("silent! noautocmd write")
    end
  end)
end

-- closing the current buffer (:bd, :q, Snacks.bufdelete) leaves it first, so
-- this covers closing too. BufUnload is too late: LSP formatters (ruff) have
-- detached by then
vim.api.nvim_create_autocmd("BufLeave", {
  group = group,
  desc = "Autosave format a buffer once it's left or closed",
  callback = function(ev)
    format_left(ev.buf)
  end,
})

vim.api.nvim_create_autocmd("VimLeavePre", {
  group = group,
  desc = "Autosave format buffers still waiting on quit",
  callback = function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      format_left(buf)
    end
  end,
})

-- :w formats fully in BufWritePre, and noautocmd autosave writes don't get here
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(ev)
    unformatted[ev.buf] = nil
  end,
})

-- a format held back above goes ahead once clangd catches up and it parses
vim.api.nvim_create_autocmd("DiagnosticChanged", {
  group = group,
  desc = "Run a held-back autosave format once clangd says the buffer parses",
  callback = function(ev)
    local buf = ev.buf
    if not format_pending[buf] or not vim.api.nvim_buf_is_valid(buf) or not parses(buf) then
      return
    end
    format_pending[buf] = nil
    -- back in the buffer since, so it waits to be left again
    if vim.api.nvim_get_current_buf() == buf then
      unformatted[buf] = true
      return
    end
    vim.api.nvim_buf_call(buf, function()
      format_buffer(buf)
      if vim.bo[buf].modified then
        vim.cmd("silent! noautocmd write")
      end
    end)
  end,
})

vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(ev)
    clangd_parse[ev.buf] = nil
    format_pending[ev.buf] = nil
    unformatted[ev.buf] = nil
  end,
})

vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "InsertLeave", "BufModifiedSet" }, {
  group = group,
  desc = "Autosave every modified buffer after a short idle delay",
  callback = function()
    timer:stop()
    timer:start(AUTOSAVE_DELAY_MS, 0, vim.schedule_wrap(save_dirty_buffers))
  end,
})

-- ---------------------------------------------------------------------------
-- Don't continue comments on <CR> or `o`/`O`.
--
-- The `r` and `o` flags in 'formatoptions' make Enter on a comment line, and
-- `o`/`O` from one, start the new line with the comment leader. Filetype
-- plugins reset 'formatoptions' per buffer, so they have to be stripped on
-- FileType rather than set once globally.
--
-- This file loads on VeryLazy, after the first buffer's FileType has already
-- fired, so buffers that are already open are fixed up here too.
-- ---------------------------------------------------------------------------
local function no_comment_continuation(buf)
  vim.bo[buf].formatoptions = vim.bo[buf].formatoptions:gsub("[ro]", "")
end

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("user_no_comment_continuation", { clear = true }),
  desc = "Don't continue comments on Enter or o/O",
  callback = function(ev)
    no_comment_continuation(ev.buf)
  end,
})

for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    no_comment_continuation(buf)
  end
end

-- ---------------------------------------------------------------------------
-- Reload files changed on disk by other tools (claude, git, formatters).
--
-- 'autoread' is on, but it only takes effect when :checktime runs, and LazyVim
-- only runs that on FocusGained / TermClose / TermLeave. Working alongside
-- claude in the sideterm column nvim never loses focus, so its edits stayed
-- invisible and the stale buffer then tripped "file changed since editing" on
-- the next edit. A 1s timer runs :checktime instead: unmodified buffers reload
-- silently, while a buffer with unsaved edits still gets nvim's reload prompt
-- rather than losing them.
-- ---------------------------------------------------------------------------
local CHECKTIME_INTERVAL_MS = 1000

local checktime_timer = assert((vim.uv or vim.loop).new_timer())
checktime_timer:start(CHECKTIME_INTERVAL_MS, CHECKTIME_INTERVAL_MS, vim.schedule_wrap(function()
  -- on the command line or at a prompt, a reload prompt would land mid-input
  if vim.api.nvim_get_mode().mode:find("^[cr]") or vim.fn.getcmdwintype() ~= "" then
    return
  end
  pcall(vim.cmd, "checktime")
end))

-- / and ? fall back to a typo-tolerant search when nothing matches exactly
require("config.fuzzy_search").setup()
