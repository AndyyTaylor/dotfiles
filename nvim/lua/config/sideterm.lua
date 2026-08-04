-- Left-hand terminal column, split into two stacked panes:
--
--   +----------+--------------------------+
--   | claude   |                          |
--   | agents   |                          |
--   +----------+   editor                 |   (file explorer opens on the right)
--   | shell    |                          |
--   |          |                          |
--   +----------+--------------------------+
--
-- Built from plain window commands rather than Snacks.terminal: snacks anchors a
-- terminal to one screen edge and does not model two panes sharing a column, so
-- there is no reliable way to express this layout through it.
--
-- Terminal buffers are kept alive when the column is closed, so toggling does not
-- kill `claude agents` or lose shell history -- reopening reattaches the same
-- buffers. The processes only die when Neovim exits.
--
-- Opened automatically at startup by config/autocmds.lua when nvim is launched on
-- a project (no args or a directory arg) -- not on one-off file edits, which would
-- spawn a `claude agents` process on every git commit.

local M = {}

M.width = 80

-- Top pane runs `claude agents` ("Manage background agents"); bottom is a plain shell.
-- Further shell panes can be stacked below with M.add() (<leader>tn); those are
-- forgotten once their shell exits, while the two builtin panes always respawn.
local PANES = {
  { key = "agents", cmd = "claude agents", builtin = true },
  { key = "shell", cmd = nil, builtin = true },
}

---@type table<string, {buf: integer?, win: integer?}>
local state = {}
for _, p in ipairs(PANES) do
  state[p.key] = { buf = nil, win = nil }
end

local function win_ok(w)
  return w ~= nil and vim.api.nvim_win_is_valid(w)
end

local function buf_ok(b)
  return b ~= nil and vim.api.nvim_buf_is_valid(b)
end

function M.is_open()
  for _, p in ipairs(PANES) do
    if win_ok(state[p.key].win) then
      return true
    end
  end
  return false
end

-- Show pane `key` in the current window, reusing its terminal buffer if it survives.
local function show(key, cmd)
  local st = state[key]
  if buf_ok(st.buf) then
    vim.api.nvim_win_set_buf(0, st.buf)
  else
    -- `:terminal {cmd}` starts the job in the current window; no cmd = $SHELL.
    if cmd then
      vim.cmd.terminal(cmd)
    else
      vim.cmd.terminal()
    end
    st.buf = vim.api.nvim_get_current_buf()
    -- Marker filetype: the bufferline offset (lua/plugins/bufferline.lua) keys off
    -- this to start the tabs to the right of the column, above the editor.
    vim.bo[st.buf].filetype = "sideterm"
  end

  -- Unlisted, so the panes don't appear in the bufferline or buffer pickers.
  vim.bo[st.buf].buflisted = false

  st.win = vim.api.nvim_get_current_win()
  local wo = vim.wo[st.win]
  wo.number = false
  wo.relativenumber = false
  wo.signcolumn = "no"
  wo.winfixwidth = true
  wo.spell = false
end

-- Even split of the column's height between the open panes.
local function equalize()
  local wins, total = {}, 0
  for _, p in ipairs(PANES) do
    local st = state[p.key]
    if win_ok(st.win) then
      wins[#wins + 1] = st.win
      total = total + vim.api.nvim_win_get_height(st.win)
    end
  end
  for i = 1, #wins - 1 do -- last window takes the remainder
    vim.api.nvim_win_set_height(wins[i], math.floor(total / #wins))
  end
end

function M.open()
  if M.is_open() then
    return M.focus("agents")
  end

  -- Forget extra panes whose shell exited while the column was closed; the
  -- builtin panes respawn their command instead.
  for i = #PANES, 1, -1 do
    local p = PANES[i]
    if not p.builtin and not buf_ok(state[p.key].buf) then
      table.remove(PANES, i)
      state[p.key] = nil
    end
  end

  local origin = vim.api.nvim_get_current_win()

  -- Full-height column pinned to the far left.
  vim.cmd("topleft vsplit")
  vim.cmd("vertical resize " .. M.width)
  show(PANES[1].key, PANES[1].cmd)

  -- Stack the remaining panes below -- the new windows stay inside the column.
  for i = 2, #PANES do
    vim.cmd("belowright split")
    show(PANES[i].key, PANES[i].cmd)
  end

  equalize()

  if vim.api.nvim_win_is_valid(origin) then
    vim.api.nvim_set_current_win(origin)
  end
end

-- Stack a new managed shell pane at the bottom of the column (opening the column
-- if needed) and leave the cursor in it. The pane behaves like the builtin ones
-- (unlisted, sideterm filetype, survives <leader>tt toggles) but is dropped from
-- the layout once its shell exits.
local extra_count = 0
function M.add()
  if not M.is_open() then
    M.open()
  end

  local bottom
  for _, p in ipairs(PANES) do
    local st = state[p.key]
    if win_ok(st.win) then
      bottom = st.win
    end
  end
  vim.api.nvim_set_current_win(bottom)

  extra_count = extra_count + 1
  local key = "shell" .. extra_count
  table.insert(PANES, { key = key, cmd = nil })
  state[key] = { buf = nil, win = nil }

  vim.cmd("belowright split")
  show(key, nil)
  equalize()
  vim.cmd("startinsert")
end

function M.close()
  for _, p in ipairs(PANES) do
    local st = state[p.key]
    if win_ok(st.win) then
      vim.api.nvim_win_close(st.win, true) -- buffer survives; process keeps running
    end
    st.win = nil
  end
end

function M.toggle()
  if M.is_open() then
    M.close()
  else
    M.open()
  end
end

-- Key of the most recently focused pane, kept up to date by a WinEnter autocmd in
-- setup(). Used so <C-h> from the editor returns to the pane you were last in,
-- rather than whichever pane is geometrically closest to the cursor row.
local last_pane

--- <C-h> replacement (normal mode): when the window to the left is a sideterm
--- pane, jump to the last-focused pane instead of the geometrically nearest one.
--- Anywhere else this is a plain `wincmd h`.
function M.smart_left()
  local cur = vim.api.nvim_get_current_win()
  local target = vim.fn.win_getid(vim.fn.winnr("h"))
  if target ~= 0 and target ~= cur then
    local tb = vim.api.nvim_win_get_buf(target)
    if vim.bo[tb].filetype == "sideterm" and last_pane and state[last_pane] and win_ok(state[last_pane].win) then
      return vim.api.nvim_set_current_win(state[last_pane].win)
    end
  end
  vim.cmd("wincmd h")
end

--- Focus a pane by key ("agents" or "shell"), opening the column if needed.
function M.focus(key)
  if not M.is_open() then
    M.open()
  end
  local st = state[key]
  if win_ok(st.win) then
    vim.api.nvim_set_current_win(st.win)
    vim.cmd("startinsert")
  end
end

function M.setup()
  vim.api.nvim_create_user_command("SideTerm", function(o)
    if o.args == "" then
      M.toggle()
    elseif o.args == "new" then
      M.add()
    else
      M.focus(o.args)
    end
  end, {
    nargs = "?",
    complete = function()
      return { "agents", "shell", "new" }
    end,
    desc = "Toggle/focus the left terminal column",
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = vim.api.nvim_create_augroup("sideterm_track", { clear = true }),
    desc = "Remember the last-focused sideterm pane",
    callback = function()
      local b = vim.api.nvim_get_current_buf()
      for _, p in ipairs(PANES) do
        local st = state[p.key]
        if st and st.buf == b then
          last_pane = p.key
          return
        end
      end
    end,
  })
end

return M
