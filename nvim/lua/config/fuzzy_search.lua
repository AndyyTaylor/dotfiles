-- Typo-tolerant fallback for / and ? searches.
--
-- When the typed search has no match anywhere in the buffer, the search is
-- cancelled (so no E486) and the buffer is scanned for the text closest to the
-- query instead, allowing a few wrong / missing / extra characters. The cursor
-- jumps to the nearest best match in the search direction, and that match's
-- actual text becomes the search pattern, so n / N / hlsearch work on the
-- corrected text.
--
-- Plain fuzzy (fzf-style subsequence) matching wasn't enough: it only forgives
-- missing characters, so a wrong or extra one still finds nothing. This uses
-- approximate substring matching instead (Sellers' edit-distance DP, with a
-- swap of two adjacent characters counting as one edit), which is
-- O(query * buffer) but only runs after an exact search has already failed.

local M = {}

-- edits allowed: short queries get fewer, or everything matches
local function max_distance(len)
  if len < 3 then
    return 0
  elseif len <= 5 then
    return 1
  end
  return 2
end

local function is_lower(b)
  return b and ((b >= 97 and b <= 122) or (b >= 48 and b <= 57))
end

local function is_upper(b)
  return b and b >= 65 and b <= 90
end

-- a and b are adjacent bytes inside one word part: _ and camelCase humps split
-- words, so both process_orders and ProcessBook have a boundary after "process"
local function joined(a, b)
  return (is_lower(a) or is_upper(a)) and (is_lower(b) or (is_upper(a) and is_upper(b)))
end

-- 0-2: how many ends of line[start..finish] cut through a word, so ties go to
-- whole words (Process over Proces)
local function cuts(line, start, finish)
  local n = 0
  if joined(line:byte(start - 1), line:byte(start)) then
    n = n + 1
  end
  if joined(line:byte(finish), line:byte(finish + 1)) then
    n = n + 1
  end
  return n
end

-- best approximate matches of query in line, as { start, finish, dist } byte
-- ranges (1-based, inclusive); one per run of overlapping end positions
local function line_matches(line, qb, k, out, lnum)
  local m = #qb
  -- columns for the previous two text positions and the current one
  local pp_d, pp_s, prev_d, prev_s, cur_d, cur_s = {}, {}, {}, {}, {}, {}
  for i = 0, m do
    prev_d[i], prev_s[i] = i, 1
  end

  local best -- best match in the current run of end positions within k
  local tb = { line:byte(1, -1) }
  for j = 1, #tb do
    local c, c_prev = tb[j], tb[j - 1]
    cur_d[0], cur_s[0] = 0, j + 1
    for i = 1, m do
      -- diagonal (match / substitution) first, so ties keep the tightest span
      local qi = qb[i]
      local d, s = prev_d[i - 1] + (qi == c and 0 or 1), prev_s[i - 1]
      if prev_d[i] + 1 < d then -- extra char in the text
        d, s = prev_d[i] + 1, prev_s[i]
      end
      if cur_d[i - 1] + 1 < d then -- query char missing from the text
        d, s = cur_d[i - 1] + 1, cur_s[i - 1]
      end
      if i > 1 and qi == c_prev and qb[i - 1] == c
          and pp_d[i - 2] + 1 < d then -- two adjacent chars swapped
        d, s = pp_d[i - 2] + 1, pp_s[i - 2]
      end
      cur_d[i], cur_s[i] = d, s
    end

    if cur_d[m] <= k then
      -- ties go to whole words, then to the span closest to the query's length
      local mt = { lnum = lnum, start = cur_s[m], finish = j, dist = cur_d[m] }
      mt.cuts, mt.slack = cuts(line, mt.start, j), math.abs(j - mt.start + 1 - m)
      if not best or mt.dist < best.dist
          or (mt.dist == best.dist and (mt.cuts < best.cuts or (mt.cuts == best.cuts and mt.slack < best.slack))) then
        best = mt
      end
    elseif best then
      out[#out + 1] = best
      best = nil
    end
    pp_d, prev_d, cur_d = prev_d, cur_d, pp_d
    pp_s, prev_s, cur_s = prev_s, cur_s, pp_s
  end
  if best then
    out[#out + 1] = best
  end
end

local function ignore_case(query)
  return vim.o.ignorecase and not (vim.o.smartcase and query:find("%u"))
end

local function fuzzy_jump(query, forward)
  local k = max_distance(#query)
  if k == 0 then
    return false
  end

  local fold = ignore_case(query)
  local qb = { (fold and query:lower() or query):byte(1, -1) }
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  -- a query char that appears nowhere in a line costs an edit wherever it
  -- aligns, so lines missing more than k of them are skipped before the DP
  local qchars = {}
  for i = 1, #qb do
    qchars[i] = string.char(qb[i])
  end
  local matches = {}
  for lnum, line in ipairs(lines) do
    local text = fold and line:lower() or line
    local absent = 0
    for i = 1, #qchars do
      if not text:find(qchars[i], 1, true) then
        absent = absent + 1
        if absent > k then
          break
        end
      end
    end
    if absent <= k then
      line_matches(text, qb, k, matches, lnum)
    end
  end
  if #matches == 0 then
    return false
  end

  -- closest text wins; among equals, the next one from the cursor (wrapping)
  local dist = math.huge
  for _, mt in ipairs(matches) do
    dist = math.min(dist, mt.dist)
  end
  local cur = vim.api.nvim_win_get_cursor(0)
  local function after(mt)
    return mt.lnum > cur[1] or (mt.lnum == cur[1] and mt.start - 1 > cur[2])
  end
  local pick, wrap
  for _, mt in ipairs(matches) do
    if mt.dist == dist then
      if forward then
        wrap = wrap or mt
        if not pick and after(mt) then
          pick = mt
        end
      else
        wrap = mt
        if not after(mt) and not (mt.lnum == cur[1] and mt.start - 1 == cur[2]) then
          pick = mt
        end
      end
    end
  end
  pick = pick or wrap

  local text = lines[pick.lnum]:sub(pick.start, pick.finish)
  local pattern = "\\V" .. (fold and "\\c" or "\\C") .. vim.fn.escape(text, "\\")
  vim.fn.setreg("/", pattern)
  vim.fn.histadd("/", pattern)
  vim.v.searchforward = forward and 1 or 0
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_cursor(0, { pick.lnum, pick.start - 1 })
  vim.v.hlsearch = 1
  vim.api.nvim_echo({ { "fuzzy: ", "Comment" }, { query .. " → " .. text } }, false, {})
  return true
end

function M.setup()
  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = vim.api.nvim_create_augroup("user_fuzzy_search", { clear = true }),
    -- "?" alone is a wildcard in autocmd patterns (matching ":" too), hence "\\?"
    pattern = { "/", "\\?" },
    desc = "Fall back to a typo-tolerant search when / or ? finds nothing",
    callback = function()
      local cmdtype = vim.v.event.cmdtype
      if vim.v.event.abort or (cmdtype ~= "/" and cmdtype ~= "?") then
        return
      end
      local query = vim.fn.getcmdline()
      local forward = cmdtype == "/"
      -- skip multi-line queries and ones with a search offset (/foo/e)
      if query == "" or query:find("\n") or query:find(forward and "[^\\]/" or "[^\\]%?") then
        return
      end

      local case = ignore_case(query) and "\\c" or "\\C"
      local ok, found = pcall(vim.fn.search, case .. query, "nw")
      if ok and found ~= 0 then
        return
      end

      -- cancel the failing search (no E486), then fall back once the cmdline is gone
      vim.cmd("let v:event.abort = v:true")
      vim.schedule(function()
        if not fuzzy_jump(query, forward) then
          vim.api.nvim_echo({ { "E486: Pattern not found: " .. query, "ErrorMsg" } }, false, {})
        end
      end)
    end,
  })
end

return M
