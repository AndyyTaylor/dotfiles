local M = {}

local active = false
local explorer_was_open = false

local function close_all(source)
  for _, p in ipairs(Snacks.picker.get({ source = source })) do
    p:close()
  end
end

local saved = {}

local function nav_keys()
  return { J = { M.next_hunk, "Review: Next Hunk" }, K = { M.prev_hunk, "Review: Prev Hunk" } }
end

local function bind(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
    return
  end

  vim.api.nvim_buf_call(buf, function()
    saved[buf] = saved[buf] or {}
    for key, spec in pairs(nav_keys()) do
      local m = vim.fn.maparg(key, "n", false, true)
      if m.desc ~= spec[2] then
        saved[buf][key] = m.buffer == 1 and m or false
        vim.keymap.set("n", key, spec[1], { buffer = buf, desc = spec[2] })
      end
    end
  end)
end

local function unbind_all()
  for buf, keys in pairs(saved) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_call(buf, function()
        for key, m in pairs(keys) do
          if vim.fn.maparg(key, "n", false, true).desc == nav_keys()[key][2] then
            vim.keymap.del("n", key, { buffer = buf })
          end
          if m then
            vim.fn.mapset(m)
          end
        end
      end)
    end
  end
  saved = {}
end

local function set_nav_keys(on)
  local group = vim.api.nvim_create_augroup("review_nav_keys", { clear = true })
  if not on then
    return unbind_all()
  end

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      bind(buf)
    end
  end
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(ev)
      bind(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(ev)
      vim.defer_fn(function()
        bind(ev.buf)
      end, 300)
    end,
  })
end

function M.toggle()
  active = not active

  local gs = require("gitsigns")
  gs.toggle_deleted(active)
  gs.toggle_linehl(active)
  gs.toggle_word_diff(active)
  set_nav_keys(active)

  if active then
    explorer_was_open = #Snacks.picker.get({ source = "explorer" }) > 0
    close_all("explorer")
    Snacks.picker.git_status({
      title = "Unstaged",
      focus = "list",
      auto_close = false,
      jump = { close = false },
      layout = { preset = "sidebar", preview = false, layout = { position = "right" } },
      transform = function(item)
        return item.status:sub(2, 2) ~= " "
      end,
      win = { list = { keys = { ["l"] = "confirm" } } },
    })
  else
    close_all("git_status")
    if explorer_was_open then
      Snacks.explorer({ cwd = LazyVim.root(), enter = false })
    end
  end
end

local function git(root, args)
  return vim.system(vim.list_extend({ "git", "-C", root }, args), { text = true }):wait().stdout
end

local function unstaged_files(root)
  local entries = vim.split(git(root, { "status", "-uall", "--porcelain=v1", "-z" }), "\0", { trimempty = true })
  local files = {}
  local i = 1
  while i <= #entries do
    local xy, file = entries[i]:match("^(..) (.+)$")
    local y = xy:sub(2, 2)
    if y ~= " " and y ~= "D" then
      files[#files + 1] = { file = file, untracked = xy == "??" }
    end
    i = i + (xy:find("[RC]") and 2 or 1)
  end

  return files
end

local function hunk_starts(root, f)
  if f.untracked then
    return { 1 }
  end

  local starts = {}
  for start in git(root, { "diff", "-U0", "--no-color", "--", f.file }):gmatch("\n@@ %-[%d,]+ %+(%d+)") do
    starts[#starts + 1] = math.max(1, tonumber(start))
  end
  if #starts == 0 then
    starts[1] = 1
  end

  return starts
end

local function jump(line)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  vim.cmd("normal! zz")
end

local function step(dir)
  local line = vim.api.nvim_win_get_cursor(0)[1]
  local hunks = require("gitsigns").get_hunks()
  if hunks then
    local from, to = 1, #hunks
    if dir < 0 then
      from, to = #hunks, 1
    end
    for i = from, to, dir do
      local start = math.max(1, hunks[i].added.start)
      if (start - line) * dir > 0 then
        return jump(start)
      end
    end
  end

  local root = vim.trim(git(vim.fn.getcwd(), { "rev-parse", "--show-toplevel" }))
  local files = unstaged_files(root)
  if #files == 0 then
    return vim.notify("No unstaged changes")
  end

  local current = vim.fs.relpath(root, vim.api.nvim_buf_get_name(0))
  local idx = dir > 0 and 0 or #files + 1
  for i, f in ipairs(files) do
    if f.file == current then
      idx = i
    end
  end

  local f = files[(idx - 1 + dir) % #files + 1]
  vim.cmd.edit(vim.fn.fnameescape(root .. "/" .. f.file))
  local starts = hunk_starts(root, f)
  jump(dir > 0 and starts[1] or starts[#starts])

  for _, p in ipairs(Snacks.picker.get({ source = "git_status" })) do
    for i, item in ipairs(p:items()) do
      if item.file == f.file then
        p.list:move(i, true)
      end
    end
  end
end

function M.next_hunk()
  step(1)
end

function M.prev_hunk()
  step(-1)
end

return M
