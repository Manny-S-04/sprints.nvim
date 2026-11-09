local html = require("sprints.html")
local items = require("sprints.api.items")
local markdown = require("sprints.markdown")
local util = require("sprints.ui.util")
local workspace = require("sprints.api.workspace")

local M = {}

local FIELD_ORDER = { "status", "type", "priority", "points", "owners", "sprint" }
local LABELS = { status = "Status", type = "Type", priority = "Priority", points = "Points", owners = "Owners", sprint = "Sprint" }

function M.parse(lines)
  local out = { title = "", fields = {}, description = "", unknown = {} }
  local i = 1
  while i <= #lines and not lines[i]:match("%S") do
    i = i + 1
  end
  if lines[i] and lines[i]:match("^%s*#") then
    out.title = vim.trim((lines[i]:gsub("^%s*#+%s*", "")))
    i = i + 1
  end
  local in_fields = true
  local desc = {}
  for j = i, #lines do
    local line = lines[j]
    if in_fields then
      if line:match("^%-%-%-+%s*$") then
        in_fields = false
      elseif line:match("%S") then
        local k, v = line:match("^%s*([%a ]-)%s*:%s*(.-)%s*$")
        if k and LABELS[k:lower()] then
          out.fields[k:lower()] = v
        else
          table.insert(out.unknown, line)
        end
      end
    else
      table.insert(desc, line)
    end
  end
  out.description = vim.trim(table.concat(desc, "\n"))
  return out
end

local function find_by_name(tbl, name)
  local want = name:lower()
  local prefix_hits = {}
  for id, row in pairs(tbl or {}) do
    local n = (row.name or ""):lower()
    if n == want then
      return id
    end
    if n:find(want, 1, true) == 1 or n:find(" " .. want, 1, true) then
      table.insert(prefix_hits, id)
    end
  end
  if #prefix_hits == 1 then
    return prefix_hits[1]
  end
  return nil, #prefix_hits > 1 and "ambiguous" or "unknown"
end

local function choices(tbl, order)
  local names = {}
  if order and #order > 0 then
    for _, id in ipairs(order) do
      if tbl[id] then
        table.insert(names, tbl[id].name)
      end
    end
  else
    for _, row in pairs(tbl or {}) do
      table.insert(names, row.name)
    end
    table.sort(names)
  end
  return names
end

function M.resolve(parsed, original, ctx)
  local meta, errors, fields = ctx.meta, {}, {}
  if parsed.title == "" then
    table.insert(errors, "the first line must be the title (# Title)")
  end
  if #parsed.unknown > 0 then
    table.insert(errors, "not a field: " .. parsed.unknown[1] .. " (put the description below ---)")
  end

  local function pick(label, tbl, value, order)
    if value == nil or value == "" then
      return nil
    end
    local id, why = find_by_name(tbl, value)
    if not id then
      table.insert(errors, ("%s %q is %s; one of: %s"):format(label, value, why, table.concat(choices(tbl, order), ", ")))
    end
    return id
  end

  local f = parsed.fields
  local status_id = pick("Status", meta.statuses, f.status, meta.status_order)
  local type_id = pick("Type", meta.types, f.type, meta.type_order)
  local priority_id = pick("Priority", meta.priorities, f.priority, meta.priority_order)

  local points = nil
  if f.points and f.points ~= "" then
    points = tonumber(f.points)
    if not points then
      table.insert(errors, ("Points %q isn't a number"):format(f.points))
    end
  end

  local owner_ids = nil
  if f.owners ~= nil then
    owner_ids = {}
    for name in (f.owners .. ","):gmatch("%s*(.-)%s*,") do
      if name ~= "" and name ~= "-" and name:lower() ~= "none" then
        local id
        if name:lower() == "me" then
          id = ctx.me
          if not id then
            table.insert(errors, '"me" needs user_id or email configured')
          end
        else
          id = pick("Owner", meta.users, name)
        end
        if id and not vim.tbl_contains(owner_ids, id) then
          table.insert(owner_ids, id)
        end
      end
    end
  end

  local sprint_id = nil
  if not original and f.sprint and f.sprint ~= "" and ctx.sprints then
    sprint_id = pick("Sprint", ctx.sprints, f.sprint)
  end

  if #errors > 0 then
    return nil, table.concat(errors, "\n")
  end

  local desc_html = markdown.to_html(parsed.description)
  if original then
    local function changed(new, old)
      return new ~= nil and tostring(new) ~= tostring(old or "")
    end
    if parsed.title ~= (original.summary or "") then
      fields.name = parsed.title
    end
    if parsed.description ~= table.concat(html.to_lines(original.description), "\n") then
      fields.description = desc_html
    end
    if changed(status_id, original.status_id) then
      fields.status_id = status_id
    end
    if changed(type_id, original.type_id) then
      fields.type_id = type_id
    end
    if changed(priority_id, original.priority_id) then
      fields.priority_id = priority_id
    end
    if f.points ~= nil and tostring(points or "") ~= tostring(original.points or "") then
      fields.points = points or ""
    end
    if owner_ids then
      local a, b = vim.deepcopy(owner_ids), vim.deepcopy(original.owner_ids or {})
      table.sort(a)
      table.sort(b)
      if not vim.deep_equal(a, b) then
        fields.owner_ids = owner_ids
      end
    end
  else
    fields = {
      name = parsed.title,
      description = parsed.description ~= "" and desc_html or nil,
      type_id = type_id,
      priority_id = priority_id,
      points = points,
      owner_ids = owner_ids and #owner_ids > 0 and owner_ids or nil,
    }
  end
  return fields, nil, sprint_id
end

local CHANGE_NAMES = {
  name = "title",
  description = "description",
  status_id = "status",
  type_id = "type",
  priority_id = "priority",
  points = "points",
  owner_ids = "owners",
}
local CHANGE_ORDER = { "name", "status_id", "owner_ids", "priority_id", "type_id", "points", "description" }

function M.describe_changes(fields)
  local out = {}
  for _, k in ipairs(CHANGE_ORDER) do
    if fields[k] ~= nil then
      table.insert(out, CHANGE_NAMES[k])
    end
  end
  return table.concat(out, ", ")
end

function M.default_priority(meta)
  for id, row in pairs(meta.priorities or {}) do
    local n = (row.name or ""):lower()
    if n == "medium" or n == "normal" or n == "none" then
      return id
    end
  end
  local order = meta.priority_order or {}
  return order[math.ceil(#order / 2)]
end

function M.template(item, meta, extra)
  local function name(tbl, id)
    return id and tbl[id] and tbl[id].name or ""
  end
  local owners = {}
  for _, id in ipairs(item and item.owner_ids or {}) do
    table.insert(owners, name(meta.users, id) ~= "" and name(meta.users, id) or id)
  end
  local values = {
    status = item and name(meta.statuses, item.status_id) or nil,
    type = name(meta.types, item and item.type_id or (extra and extra.type_id)),
    priority = name(meta.priorities, item and item.priority_id or (extra and extra.priority_id)),
    points = item and item.points and tostring(item.points) or "",
    owners = item and table.concat(owners, ", ") or "me",
    sprint = not item and extra and extra.sprint_name or nil,
  }
  local lines = { "# " .. (item and item.summary or ""), "" }
  for _, k in ipairs(FIELD_ORDER) do
    if values[k] ~= nil then
      table.insert(lines, LABELS[k] .. ": " .. values[k])
    end
  end
  table.insert(lines, "---")
  vim.list_extend(lines, item and html.to_lines(item.description) or { "" })
  return lines
end

local ns = vim.api.nvim_create_namespace("sprints.nvim.edit")

local function show_hints(bufnr, meta, sprint_names)
  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  local hints = {
    status = table.concat(choices(meta.statuses, meta.status_order), " | "),
    type = table.concat(choices(meta.types, meta.type_order), " | "),
    priority = table.concat(choices(meta.priorities, meta.priority_order), " | "),
    owners = "names, first names or me; comma-separated; empty = none",
    points = "number, or empty",
    sprint = sprint_names and table.concat(sprint_names, " | ") or nil,
  }
  for i, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    if line:match("^%-%-%-") then
      break
    end
    local k = line:match("^%s*([%a ]-)%s*:")
    local hint = k and hints[k:lower()]
    if hint then
      vim.api.nvim_buf_set_extmark(bufnr, ns, i - 1, 0, { virt_text = { { "  " .. hint, "Comment" } }, virt_text_pos = "eol" })
    end
  end
end

local function open_buffer(name, lines, meta, sprint_names, winbar, on_save)
  local bufnr = util.find_buf_by_name(name)
  if bufnr then
    util.show(bufnr)
    return bufnr
  end
  bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(bufnr, name)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].filetype = "markdown"
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified = false
  show_hints(bufnr, meta, sprint_names)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = bufnr,
    callback = function()
      show_hints(bufnr, meta, sprint_names)
    end,
  })
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      on_save(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), function(ok)
        if ok and vim.api.nvim_buf_is_valid(bufnr) then
          vim.bo[bufnr].modified = false
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end)
    end,
  })
  util.show(bufnr)
  vim.wo.winbar = winbar
  return bufnr
end

function M.edit(item, on_saved)
  local ref = item.ref
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load project fields", err)
    end
    local name = ("sprints://%s/%s/edit"):format(ref.project, ref.item)
    open_buffer(name, M.template(item, meta), meta, nil, ("Edit %s — :w saves, :q! cancels"):format(item.key),
      function(lines, done)
        workspace.me(ref.team, ref.project, function(me)
          local fields, perr = M.resolve(M.parse(lines), item, { meta = meta, me = me })
          if not fields then
            vim.notify("sprints.nvim: not saved:\n" .. perr, vim.log.levels.ERROR)
            return done(false)
          end
          if next(fields) == nil then
            vim.notify("sprints.nvim: nothing changed")
            return done(true)
          end
          items.update(ref, fields, function(ok, uerr)
            if not ok then
              util.notify_error("save failed (your text is kept)", uerr)
              return done(false)
            end
            vim.notify(("sprints.nvim: %s saved: %s"):format(item.key, M.describe_changes(fields)))
            done(true)
            if on_saved then
              on_saved()
            end
          end)
        end)
      end)
  end)
end

function M.new(target, on_created)
  local sprints_api = require("sprints.api.sprints")
  workspace.meta(target.team, target.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load project fields", err)
    end
    sprints_api.list(target.team, target.project, function(list)
      local sprint_tbl, sprint_names = {}, {}
      for _, s in ipairs(list or {}) do
        if s.state == "active" or s.state == "upcoming" then
          sprint_tbl[s.id] = { name = s.name }
          table.insert(sprint_names, s.name)
        end
      end
      sprints_api.backlog_id(target.team, target.project, function(backlog)
        if backlog then
          sprint_tbl[backlog] = { name = "Backlog" }
          table.insert(sprint_names, "Backlog")
        end
        sprint_tbl[target.sprint] = sprint_tbl[target.sprint] or { name = target.sprint_name or target.sprint }
        local lines = M.template(nil, meta, {
          sprint_name = sprint_tbl[target.sprint].name,
          type_id = (meta.type_order or {})[1],
          priority_id = M.default_priority(meta),
        })
        local bufnr = open_buffer(("sprints://%s/new"):format(target.project), lines, meta, sprint_names,
          "New item — write the title on line 1, :w creates, :q! cancels", function(buf_lines, done)
            workspace.me(target.team, target.project, function(me)
              local fields, perr, sprint_id = M.resolve(M.parse(buf_lines), nil,
                { meta = meta, me = me, sprints = sprint_tbl })
              if not fields then
                vim.notify("sprints.nvim: not created:\n" .. perr, vim.log.levels.ERROR)
                return done(false)
              end
              local where = { team = target.team, project = target.project, sprint = sprint_id or target.sprint }
              items.create(where, fields, function(new_ref, cerr)
                if not new_ref then
                  util.notify_error("create failed (your text is kept)", cerr)
                  return done(false)
                end
                vim.notify(("sprints.nvim: created %q in %s"):format(fields.name, sprint_tbl[where.sprint].name))
                done(true)
                if on_created then
                  on_created(new_ref)
                end
              end)
            end)
          end)
        vim.api.nvim_win_set_cursor(0, { 1, 2 })
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.cmd("startinsert!")
        end
      end)
    end)
  end)
end

return M
