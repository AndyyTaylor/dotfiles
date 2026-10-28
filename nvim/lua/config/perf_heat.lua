local M = {}

M.width = 80

local api = vim.api
local ns_src = api.nvim_create_namespace("perf_heat_src")
local ns_asm = api.nvim_create_namespace("perf_heat_asm")
local ns_cur = api.nvim_create_namespace("perf_heat_cur")

local LEVELS = { "#040910", "#070e1a", "#0a1426", "#0d1c35", "#112546", "#163059", "#1b3b6f", "#214888" }
local MIN_SHARE = 1e-4
local EXP_ROOT = "~/dex_tmp"
local THREAD_ORDER = { main = 1, ["in"] = 2, l1 = 3, l0 = 4 }
local RUN_ID = "^%d%d%d%d%d%d%d%d_%d%d%d%d%d%d_[%w_%-%.]+$"

local state = {
  heat = nil,
  path = nil,
  lines = {},
  line_funcs = {},
  max_own = 1,
  src_win = nil,
  key = nil,
  rows = {},
  line_row = {},
  asm_win = nil,
  asm_buf = nil,
  func = nil,
  thread = "all",
  sort = "self",
}

local function key_of(path)
  local rel = path:match("/cpp/(.+)$")
  return rel and ("cpp/" .. rel) or path
end

local function resolve(path)
  local rel = path:match("/cpp/(.+)$")
  local root = vim.fs.root(0, ".git")
  if rel and root then
    local local_path = root .. "/cpp/" .. rel
    if vim.uv.fs_stat(local_path) then
      return local_path
    end
  end
  return path
end

local function short(path)
  return path:match("/cpp/(.+)$") or vim.fn.fnamemodify(path, ":t")
end

local function share(n)
  return n / math.max(state.heat.samples, 1)
end

local function pct(n)
  return string.format("%5.2f%%", 100 * share(n))
end

local function level(n, max)
  if n <= 0 or max <= 0 then
    return nil
  end
  return math.max(1, math.min(#LEVELS, math.ceil(#LEVELS * math.sqrt(n / max))))
end

local function frames(insn)
  local out = {}
  local flat = insn[4]
  for i = 1, #flat, 2 do
    out[#out + 1] = { file = state.heat.files[flat[i] + 1], line = flat[i + 1] }
  end
  return out
end

local function own_frame(insn)
  return frames(insn)[insn[5] + 1]
end

local function set_highlights()
  for i, color in ipairs(LEVELS) do
    api.nvim_set_hl(0, "PerfHeat" .. i, { bg = color, default = true })
  end
  api.nvim_set_hl(0, "PerfHeatPct", { fg = "#89b4fa", bold = true, default = true })
  api.nvim_set_hl(0, "PerfHeatIncl", { fg = "#6c7086", default = true })
  api.nvim_set_hl(0, "PerfAsmAddr", { fg = "#585b70", default = true })
  api.nvim_set_hl(0, "PerfAsmLoc", { fg = "#6c7086", default = true })
  api.nvim_set_hl(0, "PerfAsmMatch", { fg = "#f9e2af", default = true })
  api.nvim_set_hl(0, "PerfSrcCur", { bg = "#2b2240", default = true })
  api.nvim_set_hl(0, "PerfTab", { fg = "#6c7086", default = true })
  api.nvim_set_hl(0, "PerfTabActive", { fg = "#010101", bg = "#89b4fa", bold = true, default = true })
  api.nvim_set_hl(0, "PerfTabSep", { fg = "#313244", default = true })
end

local function index(heat)
  state.lines = {}
  state.line_funcs = {}
  state.max_own = 1
  for _, row in ipairs(heat.lines) do
    local key = key_of(heat.files[row[1] + 1])
    state.lines[key] = state.lines[key] or {}
    state.lines[key][row[2]] = { self = row[3], own = row[4], incl = row[5] }
    state.max_own = math.max(state.max_own, row[4])
  end

  for fi, func in ipairs(heat.functions) do
    for _, insn in ipairs(func.insns) do
      local flat = insn[4]
      for i = 1, #flat, 2 do
        local key = key_of(heat.files[flat[i] + 1])
        local by_line = state.line_funcs[key] or {}
        state.line_funcs[key] = by_line
        by_line[flat[i + 1]] = by_line[flat[i + 1]] or {}
        by_line[flat[i + 1]][fi] = true
      end
    end
  end
end

local function annotate(buf)
  if not state.heat or not api.nvim_buf_is_valid(buf) then
    return
  end
  api.nvim_buf_clear_namespace(buf, ns_src, 0, -1)
  local name = api.nvim_buf_get_name(buf)
  local by_line = name ~= "" and state.lines[key_of(name)]
  if not by_line then
    return
  end

  local n_lines = api.nvim_buf_line_count(buf)
  for line, h in pairs(by_line) do
    if line >= 1 and line <= n_lines and math.max(share(h.own), share(h.incl)) >= MIN_SHARE then
      local virt = {}
      if share(h.own) >= MIN_SHARE then
        virt[#virt + 1] = { " " .. pct(h.own), "PerfHeatPct" }
      end
      if h.incl > h.own and share(h.incl - h.own) >= MIN_SHARE then
        virt[#virt + 1] = { " Σ" .. vim.trim(pct(h.incl)), "PerfHeatIncl" }
      end
      local lvl = level(h.own, state.max_own)
      api.nvim_buf_set_extmark(buf, ns_src, line - 1, 0, {
        line_hl_group = lvl and ("PerfHeat" .. lvl) or nil,
        virt_text = virt,
        virt_text_pos = "eol",
        priority = 50,
      })
    end
  end
end

local function annotate_all()
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) then
      annotate(buf)
    end
  end
end

local function heat_path(target)
  if vim.fn.isdirectory(vim.fn.expand(target)) == 1 then
    return vim.fn.expand(target) .. "/perf_heat.json"
  elseif not target:find("/") and not target:match("%.json$") then
    return vim.fn.expand(EXP_ROOT .. "/" .. target .. "/perf_heat.json")
  end
  return vim.fn.expand(target)
end

local function clipboard_run()
  local ok, text = pcall(vim.fn.getreg, "+")
  text = ok and vim.trim(text or "") or ""
  if text:match(RUN_ID) and vim.fn.filereadable(heat_path(text)) == 1 then
    return text
  end
end

function M.load(target)
  local path = heat_path(target)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("perf_heat: no perf_heat.json for " .. target, vim.log.levels.WARN)
    return false
  end

  local file = io.open(path, "r")
  local heat = vim.json.decode(file:read("*a"))
  file:close()
  state.heat = heat
  state.path = path
  index(heat)
  annotate_all()
  vim.notify(
    string.format(
      "perf_heat: %s samples, %.1f%% in dex, %d functions (%s)",
      heat.samples,
      100 * heat.binary_samples / math.max(heat.samples, 1),
      #heat.functions,
      vim.fn.fnamemodify(path, ":h:t")
    )
  )
  return true
end

function M.pick(on_loaded)
  on_loaded = on_loaded or function() end
  local run = clipboard_run()
  if run then
    if M.load(run) then
      on_loaded()
    end
    return
  end
  vim.ui.input({ prompt = "perf run id: " }, function(input)
    input = input and vim.trim(input) or ""
    if input ~= "" and M.load(input) then
      on_loaded()
    end
  end)
end

local function with_heat(fn)
  if state.heat then
    fn()
  else
    M.pick(fn)
  end
end

function M.toggle()
  if state.heat then
    M.off()
  else
    M.pick()
  end
end

local function asm_open()
  return state.asm_win ~= nil and api.nvim_win_is_valid(state.asm_win)
end

local function close_asm()
  if asm_open() then
    api.nvim_win_close(state.asm_win, true)
  end
end

function M.off()
  state.heat = nil
  for _, buf in ipairs(api.nvim_list_bufs()) do
    api.nvim_buf_clear_namespace(buf, ns_src, 0, -1)
    api.nvim_buf_clear_namespace(buf, ns_cur, 0, -1)
  end
  close_asm()
  state.func = nil
end

local function loc(frame)
  if key_of(frame.file) == state.key then
    return ":" .. frame.line
  end
  return short(frame.file) .. ":" .. frame.line
end

local function set_winbar(status)
  if not asm_open() then
    return
  end
  local func = state.heat.functions[state.func]
  local text = string.format(" %s  %s  %s", status, vim.trim(pct(func.samples)), func.name)
  vim.wo[state.asm_win].winbar = "%#PerfAsmLoc#" .. text:gsub("%%", "%%%%")
end

local function render(fi, key)
  local func = state.heat.functions[fi]
  state.func = fi
  state.key = key

  local by_line = {}
  local other = {}
  local lo, hi
  for _, insn in ipairs(func.insns) do
    local line
    for _, frame in ipairs(frames(insn)) do
      if key_of(frame.file) == key then
        line = frame.line
      end
    end
    if line then
      by_line[line] = by_line[line] or {}
      table.insert(by_line[line], insn)
      lo = math.min(lo or line, line)
      hi = math.max(hi or line, line)
    else
      other[#other + 1] = insn
    end
  end

  local rows = {}
  state.line_row = {}
  for line = lo or 1, hi or 0 do
    state.line_row[line] = #rows + 1
    for k, insn in ipairs(by_line[line] or { false }) do
      rows[#rows + 1] = { line = line, insn = insn or nil, first = k == 1 }
    end
  end
  for k, insn in ipairs(other) do
    rows[#rows + 1] = { insn = insn, first = k == 1 }
  end
  state.rows = rows

  local max = 0
  for _, insn in ipairs(func.insns) do
    max = math.max(max, insn[3])
  end
  local lines = {}
  for _, row in ipairs(rows) do
    local insn = row.insn
    lines[#lines + 1] = insn
        and string.format("%s %8x  %s", insn[3] > 0 and pct(insn[3]) or string.rep(" ", 6), insn[1], insn[2])
      or ""
  end

  local buf = state.asm_buf
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns_asm, 0, -1)
  for i, row in ipairs(rows) do
    local insn = row.insn
    if insn then
      local lvl = level(insn[3], max)
      local own = own_frame(insn)
      local label = row.line and (":" .. row.line) or (own and loc(own))
      api.nvim_buf_set_extmark(buf, ns_asm, i - 1, 0, {
        line_hl_group = lvl and ("PerfHeat" .. lvl) or nil,
        virt_text = row.first and label and { { label, "PerfAsmLoc" } } or nil,
        virt_text_pos = "right_align",
      })
      api.nvim_buf_set_extmark(buf, ns_asm, i - 1, 0, { end_col = 6, hl_group = "PerfHeatPct" })
      api.nvim_buf_set_extmark(buf, ns_asm, i - 1, 7, { end_col = 15, hl_group = "PerfAsmAddr" })
    end
  end
end

local function mark(line)
  api.nvim_buf_clear_namespace(state.asm_buf, ns_cur, 0, -1)
  local first
  local n = 0
  for i, row in ipairs(state.rows) do
    if row.insn then
      for _, frame in ipairs(frames(row.insn)) do
        if frame.line == line and key_of(frame.file) == state.key then
          api.nvim_buf_set_extmark(state.asm_buf, ns_cur, i - 1, 0, { sign_text = "▌", sign_hl_group = "PerfAsmMatch" })
          first = first or i
          n = n + 1
          break
        end
      end
    end
  end
  return n, first
end

local function status(line, n)
  return string.format(":%d %s", line, n > 0 and (n .. " insns") or "no code")
end

local function align(from_win, to_win, to_row)
  local offset = api.nvim_win_call(from_win, vim.fn.winline) - 1
  api.nvim_win_set_cursor(to_win, { to_row, 0 })
  api.nvim_win_call(to_win, function()
    vim.fn.winrestview({ topline = math.max(1, to_row - offset) })
  end)
end

local function hottest_func(key, line)
  local best
  for fi in pairs((state.line_funcs[key] or {})[line] or {}) do
    if fi == state.func and key == state.key then
      return fi
    end
    if not best or state.heat.functions[fi].samples > state.heat.functions[best].samples then
      best = fi
    end
  end
  return best
end

local function follow(key, line)
  local fi = (state.func and key == state.key and state.line_row[line]) and state.func or hottest_func(key, line)
  if not fi then
    api.nvim_buf_clear_namespace(state.asm_buf, ns_cur, 0, -1)
    set_winbar(status(line, 0))
    return
  end
  if fi ~= state.func or key ~= state.key then
    render(fi, key)
  end
  local n, first = mark(line)
  set_winbar(status(line, n))
  local row = state.line_row[line] or first
  if row then
    align(state.src_win, state.asm_win, row)
  end
end

local function is_src(win)
  local buf = api.nvim_win_get_buf(win)
  return win ~= state.asm_win and vim.bo[buf].buftype == "" and api.nvim_buf_get_name(buf) ~= ""
end

local function on_src_moved()
  if not (state.heat and asm_open()) then
    return
  end
  local win = api.nvim_get_current_win()
  if not is_src(win) then
    return
  end
  state.src_win = win
  local buf = api.nvim_win_get_buf(win)
  api.nvim_buf_clear_namespace(buf, ns_cur, 0, -1)
  follow(key_of(api.nvim_buf_get_name(buf)), api.nvim_win_get_cursor(win)[1])
end

local function on_scrolled()
  local win = api.nvim_get_current_win()
  if not (state.heat and asm_open() and win == state.src_win and vim.v.event[tostring(win)]) then
    return
  end
  if key_of(api.nvim_buf_get_name(api.nvim_win_get_buf(win))) ~= state.key then
    return
  end
  local row = state.line_row[api.nvim_win_get_cursor(win)[1]]
  if row then
    align(win, state.asm_win, row)
  end
end

local function lock_src(line)
  local win = state.src_win
  if not (win and api.nvim_win_is_valid(win)) then
    return false
  end
  local buf = api.nvim_win_get_buf(win)
  if key_of(api.nvim_buf_get_name(buf)) ~= state.key or line > api.nvim_buf_line_count(buf) then
    return false
  end
  api.nvim_buf_clear_namespace(buf, ns_cur, 0, -1)
  api.nvim_buf_set_extmark(buf, ns_cur, line - 1, 0, { line_hl_group = "PerfSrcCur", priority = 60 })
  align(state.asm_win, win, line)
  return true
end

local function goto_frame(frame)
  if not frame or not (state.src_win and api.nvim_win_is_valid(state.src_win)) then
    return
  end
  api.nvim_win_call(state.src_win, function()
    if key_of(api.nvim_buf_get_name(0)) ~= key_of(frame.file) then
      vim.cmd.edit(vim.fn.fnameescape(resolve(frame.file)))
    end
    if frame.line <= api.nvim_buf_line_count(0) then
      api.nvim_win_set_cursor(0, { frame.line, 0 })
      vim.cmd("normal! zz")
    end
  end)
  api.nvim_set_current_win(state.src_win)
end

local function row_at_cursor()
  return state.func and state.rows[api.nvim_win_get_cursor(0)[1]]
end

local function on_asm_moved()
  local row = row_at_cursor()
  if not row then
    return
  end
  if row.line then
    set_winbar(status(row.line, (mark(row.line))))
  else
    api.nvim_buf_clear_namespace(state.asm_buf, ns_cur, 0, -1)
  end
  if row.insn then
    local chain = {}
    for _, frame in ipairs(frames(row.insn)) do
      chain[#chain + 1] = loc(frame)
    end
    if #chain > 1 then
      api.nvim_buf_set_extmark(state.asm_buf, ns_cur, api.nvim_win_get_cursor(0)[1] - 1, 0, {
        virt_lines = { { { "  " .. table.concat(chain, " ← "), "PerfAsmLoc" } } },
      })
    end
  end
  if row.line then
    lock_src(row.line)
  end
end

local function ensure_asm_buf()
  if state.asm_buf and api.nvim_buf_is_valid(state.asm_buf) then
    return
  end
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].filetype = "asm"
  api.nvim_buf_set_name(buf, "perf://asm")
  state.asm_buf = buf
  local map = function(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true })
  end
  map("<CR>", function()
    local row = row_at_cursor()
    if row and row.line and lock_src(row.line) then
      api.nvim_set_current_win(state.src_win)
    elseif row and row.insn then
      goto_frame(own_frame(row.insn))
    end
  end)
  map("L", function()
    local row = row_at_cursor()
    goto_frame(row and row.insn and frames(row.insn)[1])
  end)
  map("]h", function()
    M.next_hot(1)
  end)
  map("[h", function()
    M.next_hot(-1)
  end)
  map("q", close_asm)
  api.nvim_create_autocmd("CursorMoved", { buffer = buf, callback = on_asm_moved })
end

local function open_asm_win()
  local explorers = _G.Snacks and Snacks.picker.get({ source = "explorer" }) or {}
  local explorer_was_open = #explorers > 0
  for _, picker in ipairs(explorers) do
    picker:close()
  end

  vim.cmd("botright vsplit")
  local win = api.nvim_get_current_win()
  state.asm_win = win
  api.nvim_win_set_buf(win, state.asm_buf)
  api.nvim_win_set_width(win, M.width)
  vim.wo[win].winfixwidth = true
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "yes:1"
  vim.wo[win].cursorline = true
  api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      state.asm_win = nil
      if explorer_was_open then
        vim.schedule(function()
          Snacks.explorer({ cwd = LazyVim.root(), enter = false })
        end)
      end
    end,
  })
  api.nvim_set_current_win(state.src_win)
end

local function open(fi, key, line)
  ensure_asm_buf()
  if not asm_open() then
    open_asm_win()
  end
  render(fi, key)
  follow(key, line)
end

local function asm()
  state.src_win = api.nvim_get_current_win()
  local key = key_of(api.nvim_buf_get_name(0))
  local line = api.nvim_win_get_cursor(0)[1]
  local candidates = {}
  for fi in pairs((state.line_funcs[key] or {})[line] or {}) do
    candidates[#candidates + 1] = fi
  end
  if #candidates == 0 then
    vim.notify("perf_heat: no hot functions contain this line", vim.log.levels.INFO)
    return
  end
  table.sort(candidates, function(a, b)
    return state.heat.functions[a].samples > state.heat.functions[b].samples
  end)
  if #candidates == 1 then
    return open(candidates[1], key, line)
  end
  vim.ui.select(candidates, {
    prompt = "perf: functions containing this line",
    format_item = function(fi)
      local func = state.heat.functions[fi]
      return pct(func.samples) .. "  " .. func.name
    end,
  }, function(fi)
    if fi then
      open(fi, key, line)
    end
  end)
end

function M.asm()
  if asm_open() then
    close_asm()
  else
    with_heat(asm)
  end
end

function M.next_hot(direction)
  if not state.func then
    return
  end
  local max = 0
  for _, row in ipairs(state.rows) do
    if row.insn then
      max = math.max(max, row.insn[3])
    end
  end
  local i = api.nvim_win_get_cursor(0)[1] + direction
  while i >= 1 and i <= #state.rows do
    local row = state.rows[i]
    if row.insn and row.insn[3] >= 0.25 * max then
      api.nvim_win_set_cursor(0, { i, 0 })
      return
    end
    i = i + direction
  end
end

local function short_name(name)
  name = name:gsub("^std::_Function_handler<[^,]*, (.*)>::_M_invoke%b()$", "%1")
  name = name:gsub("std::__cxx11::", "std::")
  name = name:gsub(", std::allocator<[^<>]*> ?", "")
  name = name:gsub("%b()(::{lambda)", "%1")
  name = name:gsub(" const$", "")
  name = name:gsub("%b()$", "")
  return name
end

local function thread_samples(thread)
  if thread == "all" then
    return state.heat.samples
  end
  for _, t in ipairs(state.heat.threads or {}) do
    if t[1] == thread then
      return t[2]
    end
  end
  return 0
end

local function thread_tabs()
  local threads = {}
  for i, t in ipairs(state.heat.threads or {}) do
    if t[2] >= 0.001 * state.heat.samples then
      threads[#threads + 1] = { name = t[1], rank = THREAD_ORDER[t[1]] or 100 + i }
    end
  end
  table.sort(threads, function(a, b)
    return a.rank < b.rank
  end)
  local tabs = { "all" }
  for _, t in ipairs(threads) do
    tabs[#tabs + 1] = t.name
  end
  return tabs
end

local function hotspot_items(thread)
  local items = {}
  for _, sym in ipairs(state.heat.symbols or {}) do
    local total = sym.total[thread] or 0
    if total > 0 then
      local item = {
        self = sym.self[thread] or 0,
        total = total,
        fi = sym.fi and sym.fi + 1,
        name = sym.name,
        label = short_name(sym.name),
      }
      if sym.source then
        item.file = resolve(state.heat.files[sym.source[1] + 1])
        item.pos = { sym.source[2], 0 }
        item.where = short(item.file) .. ":" .. sym.source[2]
        item.preview = "file"
      else
        item.external = true
        item.where = vim.fn.fnamemodify(sym.dso, ":t")
        item.preview = { text = sym.name .. "\n\n" .. sym.dso .. "\n\nno source to drill into" }
      end
      items[#items + 1] = item
    end
  end

  local key = state.sort
  table.sort(items, function(a, b)
    if a[key] ~= b[key] then
      return a[key] > b[key]
    end
    return a.total > b.total
  end)
  for i, item in ipairs(items) do
    item.idx = i
    item.text = item.name .. " " .. (item.where or "")
  end
  return items
end

local function duration(n)
  local ms = state.heat.ms_per_sample
  if not ms then
    return ""
  end
  local t = n * ms
  if t >= 1000 then
    return string.format("%7.2fs", t / 1000)
  end
  return string.format("%6.1fms", t)
end

local function column(n, thread_total, active)
  local text = string.format("%s %5.1f%%", duration(n), 100 * n / thread_total)
  return { text, active and "PerfHeatPct" or "PerfHeatIncl" }
end

local function show_tabs(picker)
  local win = picker.list and picker.list.win and picker.list.win.win
  if not (win and api.nvim_win_is_valid(win)) then
    return
  end
  local parts = {}
  for _, tab in ipairs(thread_tabs()) do
    local share = tab == "all" and ""
      or string.format(" %d%%%%", math.floor(100 * thread_samples(tab) / state.heat.samples + 0.5))
    local hl = tab == state.thread and "PerfTabActive" or "PerfTab"
    parts[#parts + 1] = "%#" .. hl .. "# " .. tab .. share .. " "
  end
  local sort = string.format("%%=%%#PerfTab#sort: %%#PerfTabActive# %s %%#PerfTab# <c-s> self  <c-t> total ", state.sort)
  vim.wo[win].winbar = table.concat(parts, "%#PerfTabSep#│") .. sort
end

local function cycle_thread(picker, direction)
  local tabs = thread_tabs()
  local i = 1
  for k, tab in ipairs(tabs) do
    if tab == state.thread then
      i = k
    end
  end
  state.thread = tabs[(i - 1 + direction) % #tabs + 1]
  show_tabs(picker)
  picker:refresh()
end

local function sort_by(picker, key)
  state.sort = key
  show_tabs(picker)
  picker:refresh()
end

local function drill(item)
  if not item.file then
    vim.notify("perf_heat: " .. item.label .. " has no source to drill into", vim.log.levels.INFO)
    return
  end
  local win = api.nvim_get_current_win()
  if not is_src(win) then
    for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
      if is_src(w) then
        win = w
        break
      end
    end
  end
  api.nvim_set_current_win(win)
  vim.cmd.edit(vim.fn.fnameescape(item.file))
  api.nvim_win_set_cursor(win, item.pos)
  vim.cmd("normal! zz")
  state.src_win = win
  if item.fi then
    open(item.fi, key_of(item.file), item.pos[1])
  end
end

local function top()
  if not vim.tbl_contains(thread_tabs(), state.thread) then
    state.thread = "all"
  end
  Snacks.picker.pick({
    title = "Perf Hot Functions",
    finder = function()
      return hotspot_items(state.thread)
    end,
    preview = "preview",
    sort = { fields = { "idx" } },
    format = function(item)
      local thread_total = math.max(thread_samples(state.thread), 1)
      return {
        column(item.self, thread_total, state.sort == "self"),
        { "  " },
        column(item.total, thread_total, state.sort == "total"),
        { "  " },
        { item.label, item.external and "PerfHeatIncl" or "Function" },
        { "  " .. (item.where or ""), "PerfAsmLoc" },
      }
    end,
    on_show = show_tabs,
    actions = {
      perf_thread_next = function(picker)
        cycle_thread(picker, 1)
      end,
      perf_thread_prev = function(picker)
        cycle_thread(picker, -1)
      end,
      perf_sort_self = function(picker)
        sort_by(picker, "self")
      end,
      perf_sort_total = function(picker)
        sort_by(picker, "total")
      end,
      confirm = function(picker, item)
        picker:close()
        if item then
          vim.schedule(function()
            drill(item)
          end)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<Left>"] = { "perf_thread_prev", mode = { "i", "n" } },
          ["<Right>"] = { "perf_thread_next", mode = { "i", "n" } },
          ["<c-s>"] = { "perf_sort_self", mode = { "i", "n" } },
          ["<c-t>"] = { "perf_sort_total", mode = { "i", "n" } },
        },
      },
      list = {
        keys = {
          ["<Left>"] = "perf_thread_prev",
          ["<Right>"] = "perf_thread_next",
          ["<c-s>"] = "perf_sort_self",
          ["<c-t>"] = "perf_sort_total",
        },
      },
    },
  })
end

function M.top()
  with_heat(top)
end

function M.setup()
  set_highlights()
  local group = api.nvim_create_augroup("perf_heat", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_highlights })
  api.nvim_create_autocmd("BufReadPost", {
    group = group,
    callback = function(args)
      annotate(args.buf)
    end,
  })
  api.nvim_create_autocmd({ "CursorMoved", "BufEnter" }, { group = group, callback = on_src_moved })
  api.nvim_create_autocmd("WinScrolled", { group = group, callback = on_scrolled })

  api.nvim_create_user_command("PerfHeat", function(opts)
    if opts.args ~= "" then
      M.load(opts.args)
    else
      M.toggle()
    end
  end, { nargs = "?", complete = "file", desc = "toggle perf heat (run id from the clipboard, else prompt), or load a run id / path" })
  api.nvim_create_user_command("PerfAsm", M.asm, { desc = "asm + per-instruction heat for the line under the cursor" })
  api.nvim_create_user_command("PerfTop", M.top, { desc = "hot functions by self time, per thread" })
end

return M
