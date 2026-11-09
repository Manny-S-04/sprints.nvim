local html = require("sprints.html")

local M = {}

local META_FIELDS = {
  { key = "status", label = "Status" },
  { key = "assignee", label = "Owners", empty = "(none)" },
  { key = "priority", label = "Priority" },
  { key = "issue_type", label = "Type" },
  { key = "points", label = "Points" },
  { key = "sprint_name", label = "Sprint" },
  { key = "epic", label = "Epic" },
  { key = "reporter", label = "Created by" },
  { key = "updated", label = "Updated", date = true, time = true },
}

local function epoch_seconds(v)
  local n = tonumber(v)
  if not n then
    return nil
  end
  if n >= 1e11 then
    return math.floor(n / 1000)
  elseif n >= 1e8 then
    return math.floor(n)
  end
  return nil
end

---@param with_time boolean|nil include HH:MM
function M.format_date(v, with_time)
  if v == nil or v == "" then
    return ""
  end
  local secs = epoch_seconds(v)
  if secs then
    return os.date(with_time and "%Y-%m-%d %H:%M" or "%Y-%m-%d", secs)
  end
  local s = tostring(v)
  if with_time then
    local d, t = s:match("^(%d%d%d%d%-%d%d%-%d%d)[T ](%d%d:%d%d)")
    if d then
      return d .. " " .. t
    end
  end
  return s:match("^(%d%d%d%d%-%d%d%-%d%d)") or s
end

function M.render(item)
  local lines, highlights = {}, {}
  local function add(line)
    table.insert(lines, line)
    return #lines - 1
  end
  local function hl(idx, s, e, group)
    table.insert(highlights, { line = idx, col_start = s, col_end = e, hl_group = group })
  end

  local heading = "# " .. (item.key or "?")
  hl(add(heading), 0, #heading, "sprintsHeading")
  add("")
  add(item.summary or "(no name)")
  add("")

  for _, meta in ipairs(META_FIELDS) do
    local value = item[meta.key]
    if meta.date then
      value = M.format_date(value, meta.time)
    end
    if (value == nil or value == "") and meta.empty then
      value = meta.empty
    end
    if value ~= nil and value ~= "" then
      local label = meta.label .. ":"
      local idx = add(("%-14s%s"):format(label, tostring(value)))
      hl(idx, 0, #label, "sprintsLabel")
      if meta.key == "status" then
        hl(idx, 14, 14 + #tostring(value), M.status_hl(item.status_category))
      end
    end
  end

  add("")
  local dh = "## Description"
  hl(add(dh), 0, #dh, "sprintsHeading")
  add("")
  local desc = html.to_lines(item.description)
  if #desc == 0 then
    add("(no description — e to edit)")
  else
    for _, l in ipairs(desc) do
      add(l)
    end
  end

  add("")
  local n = item.comments and #item.comments or 0
  local ch = n > 0 and ("## Comments (%d)"):format(n) or "## Comments"
  hl(add(ch), 0, #ch, "sprintsHeading")
  add("")
  if item.comments_error then
    add("(comments unavailable: " .. item.comments_error .. ")")
  elseif n == 0 then
    add("(no comments — c to add one)")
  else
    for i, c in ipairs(item.comments) do
      local author = c.author or "Unknown"
      hl(add(author .. " — " .. M.format_date(c.created, true)), 0, #author, "sprintsCommentAuthor")
      for _, l in ipairs(html.to_lines(c.body)) do
        add(l)
      end
      if i < n then
        add("")
      end
    end
  end

  return lines, highlights
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

local function pad(s, w)
  return s .. string.rep(" ", math.max(0, w - width(s)))
end

function M.status_hl(category)
  if category == "done" then
    return "sprintsStatusDone"
  elseif category == "indeterminate" then
    return "sprintsStatusProgress"
  end
  return "sprintsStatusTodo"
end

function M.initials(names)
  if not names or names == "" then
    return "-"
  end
  local out = {}
  for name in (names .. ","):gmatch("%s*(.-)%s*,") do
    local letters = {}
    for word in name:gmatch("%S+") do
      table.insert(letters, vim.fn.strcharpart(word, 0, 1):upper())
      if #letters == 2 then
        break
      end
    end
    table.insert(out, name:match("^%d+$") and "?" or table.concat(letters))
  end
  return table.concat(out, " ")
end

local function grouped(items, status_order)
  local by_status, order, seen = {}, {}, {}
  for _, id in ipairs(status_order or {}) do
    table.insert(order, id)
    seen[id] = true
  end
  for _, it in ipairs(items) do
    local k = it.status_id or it.status or "?"
    if not seen[k] then
      table.insert(order, k)
      seen[k] = true
    end
    by_status[k] = by_status[k] or {}
    table.insert(by_status[k], it)
  end
  local groups = {}
  for _, k in ipairs(order) do
    if by_status[k] then
      table.insert(groups, { title = by_status[k][1].status or k, items = by_status[k] })
    end
  end
  return groups
end

function M.render_list(title, items, opts)
  opts = opts or {}
  local lines, highlights, by_line = { "# " .. title, "" }, {}, {}
  table.insert(highlights, { line = 0, col_start = 0, col_end = #lines[1], hl_group = "sprintsHeading" })
  if #items == 0 then
    table.insert(lines, "(no items)")
    return lines, highlights, by_line
  end

  local w = { key = 0, status = 0, type = 0, pts = 0, own = 0 }
  local cells = {}
  for _, it in ipairs(items) do
    local c = {
      key = it.key or "?",
      status = it.status or "",
      type = it.issue_type or "",
      pts = it.points and tostring(it.points) or "",
      own = M.initials(it.assignee),
    }
    cells[it] = c
    for k, v in pairs(c) do
      w[k] = math.max(w[k], width(v))
    end
  end

  local function row(it)
    local c = cells[it]
    local parts = { pad(c.key, w.key) }
    if not opts.group then
      table.insert(parts, pad(c.status, w.status))
    end
    table.insert(parts, pad(c.type, w.type))
    if w.pts > 0 then
      table.insert(parts, pad(c.pts, w.pts))
    end
    table.insert(parts, pad(c.own, w.own))
    table.insert(parts, it.summary or "")
    table.insert(lines, table.concat(parts, "  "))
    local idx = #lines - 1
    by_line[#lines] = it
    table.insert(highlights, { line = idx, col_start = 0, col_end = #c.key, hl_group = "sprintsKey" })
    if not opts.group then
      local s = #pad(c.key, w.key) + 2
      table.insert(highlights, { line = idx, col_start = s, col_end = s + #c.status, hl_group = M.status_hl(it.status_category) })
    end
  end

  if opts.group then
    for gi, g in ipairs(grouped(items, opts.status_order)) do
      if gi > 1 then
        table.insert(lines, "")
      end
      local h = ("## %s (%d)"):format(g.title, #g.items)
      table.insert(lines, h)
      table.insert(highlights, { line = #lines - 1, col_start = 0, col_end = #h, hl_group = M.status_hl(g.items[1].status_category) })
      for _, it in ipairs(g.items) do
        row(it)
      end
    end
  else
    for _, it in ipairs(items) do
      row(it)
    end
  end
  return lines, highlights, by_line
end

return M
