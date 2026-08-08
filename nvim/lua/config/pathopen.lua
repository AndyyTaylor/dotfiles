-- Ctrl+LeftMouse in terminal panes opens the file path under the mouse,
-- VS Code style. Code files open in the first editor window (jumping to the
-- line for path:123 tokens); images and PDFs open with the system viewer.
local M = {}

local viewer_ext = {
  png = true, jpg = true, jpeg = true, gif = true, webp = true, svg = true, pdf = true,
}

-- cwd the terminal was started in, parsed from the term://cwd//pid:cmd URI
local function term_cwd(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local cwd = name:match("^term://(.-)//")
  return (cwd and cwd ~= "") and vim.fn.expand(cwd) or vim.fn.getcwd()
end

local function path_under_mouse()
  local mp = vim.fn.getmousepos()
  if mp.winid == 0 or mp.line == 0 then return end
  local buf = vim.api.nvim_win_get_buf(mp.winid)
  if vim.bo[buf].buftype ~= "terminal" then return end
  local text = vim.api.nvim_buf_get_lines(buf, mp.line - 1, mp.line, false)[1] or ""
  local col = mp.column
  local function is_pathchar(i)
    return text:sub(i, i):match("[%w%._%-/~+:]") ~= nil
  end
  if col < 1 or col > #text or not is_pathchar(col) then return end
  local s, e = col, col
  while s > 1 and is_pathchar(s - 1) do s = s - 1 end
  while e < #text and is_pathchar(e + 1) do e = e + 1 end
  local token = text:sub(s, e)
  -- peel a trailing :123 line number, then stray punctuation
  local path, lnum = token:match("^(.-):(%d+)[.,;:]*$")
  path = (path or token):gsub("[.,;:]+$", "")
  if path == "" then return end
  return path, tonumber(lnum), buf
end

function M.open_under_mouse()
  local path, lnum, buf = path_under_mouse()
  if not path then return end
  local full = path:gsub("^~", vim.env.HOME)
  if not full:match("^/") then
    full = vim.fs.joinpath(term_cwd(buf), full)
  end
  if vim.fn.filereadable(full) == 0 then
    vim.notify("Not a file: " .. full, vim.log.levels.WARN)
    return
  end
  local ext = full:match("%.(%w+)$")
  if ext and viewer_ext[ext:lower()] then
    vim.ui.open(full)
    return
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local b = vim.api.nvim_win_get_buf(win)
    if vim.bo[b].buftype == "" and vim.api.nvim_win_get_config(win).relative == "" then
      vim.api.nvim_set_current_win(win)
      vim.cmd.edit(vim.fn.fnameescape(full))
      if lnum then
        pcall(vim.api.nvim_win_set_cursor, win, { lnum, 0 })
      end
      return
    end
  end
  vim.cmd.vsplit(vim.fn.fnameescape(full))
end

function M.setup()
  vim.keymap.set({ "n", "t" }, "<C-LeftMouse>", M.open_under_mouse, { desc = "Open path under mouse" })
end

return M
