local config = require("sprints.config")
local items = require("sprints.api.items")
local render = require("sprints.ui.render")
local util = require("sprints.ui.util")
local workspace = require("sprints.api.workspace")

local M = {}

local last_item = {}

local function buf_name(ref)
  return ("sprints://%s/%s"):format(ref.project, ref.item)
end

local function ref_of(bufnr)
  return vim.b[bufnr].sprints_ref
end

local function key_of(bufnr)
  return vim.b[bufnr].sprints_key or "item"
end

local function render_into(bufnr, item)
  local lines, highlights = render.render(item)
  util.set_lines(bufnr, lines)
  util.apply_highlights(bufnr, highlights)
  vim.b[bufnr].sprints_ref = item.ref
  vim.b[bufnr].sprints_key = item.key
  vim.b[bufnr].sprints_url = items.browse_url(item.ref, item.no)
  last_item[bufnr] = item
  util.set_readonly(bufnr, true)
end

function M.refresh(bufnr, on_done)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local ref = ref_of(bufnr)
  if not ref then
    return vim.notify("sprints.nvim: this buffer is not a Sprints item buffer", vim.log.levels.WARN)
  end
  items.get(ref, function(item, err)
    if not item then
      return util.notify_error("failed to refresh " .. key_of(bufnr), err)
    end
    if vim.api.nvim_buf_is_valid(bufnr) then
      render_into(bufnr, item)
    end
    if on_done then
      on_done()
    end
  end)
end

function M.refresh_ref(ref)
  local bufnr = util.find_buf_by_name(buf_name(ref))
  if bufnr then
    M.refresh(bufnr)
  end
end

local function after(bufnr, what)
  return function(ok, err)
    if not ok then
      return util.notify_error(what .. " failed", err)
    end
    vim.notify("sprints.nvim: " .. what)
    M.refresh(bufnr)
  end
end

function M.change_status(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  items.statuses(ref, function(list, err)
    if not list then
      return util.notify_error("could not load statuses", err)
    end
    list = vim.tbl_filter(function(s)
      return s.id ~= item.status_id
    end, list)
    if #list == 0 then
      return vim.notify("sprints.nvim: no other statuses in this project", vim.log.levels.WARN)
    end
    vim.ui.select(list, {
      prompt = ("%s is %s → "):format(key_of(bufnr), item.status or "?"),
      format_item = function(s)
        return s.name
      end,
    }, function(choice)
      if choice then
        items.set_status(ref, choice.id,
          after(bufnr, ("%s: %s → %s"):format(key_of(bufnr), item.status or "?", choice.name)))
      end
    end)
  end)
end

function M.toggle_me(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.me(ref.team, ref.project, function(me, err)
    if not me then
      return util.notify_error("could not work out who you are", err)
    end
    local mine = vim.tbl_contains(item.owner_ids or {}, me)
    items.toggle_me(ref, item.owner_ids, not mine,
      after(bufnr, ("%s: %s"):format(key_of(bufnr), mine and "removed you as owner" or "added you as owner")))
  end)
end

function M.pick_owner(bufnr)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load users", err)
    end
    local users = {}
    for id, u in pairs(meta.users) do
      table.insert(users, { id = id, name = u.name or id })
    end
    table.sort(users, function(a, b)
      return a.name < b.name
    end)
    local current = item.owner_ids or {}
    vim.ui.select(users, {
      prompt = key_of(bufnr) .. " owners (pick to add/remove)",
      format_item = function(u)
        return (vim.tbl_contains(current, u.id) and "✓ " or "  ") .. u.name
      end,
    }, function(choice)
      if not choice then
        return
      end
      local owners = vim.tbl_filter(function(id)
        return id ~= choice.id
      end, current)
      local adding = #owners == #current
      if adding then
        table.insert(owners, choice.id)
      end
      items.set_owners(ref, owners,
        after(bufnr, ("%s: %s %s"):format(key_of(bufnr), adding and "added" or "removed", choice.name)))
    end)
  end)
end

function M.unassign_all(bufnr)
  local item = last_item[bufnr] or {}
  if not item.owner_ids or #item.owner_ids == 0 then
    return vim.notify("sprints.nvim: " .. key_of(bufnr) .. " has no owners")
  end
  if util.confirm(("Remove all owners (%s) from %s?"):format(item.assignee or "", key_of(bufnr))) then
    items.set_owners(ref_of(bufnr), {}, after(bufnr, key_of(bufnr) .. ": removed all owners"))
  end
end

local function pick_field(bufnr, tbl_name, order_name, field, label)
  local ref, item = ref_of(bufnr), last_item[bufnr] or {}
  workspace.meta(ref.team, ref.project, function(meta, err)
    if not meta then
      return util.notify_error("could not load " .. label:lower() .. "s", err)
    end
    local list = {}
    for _, id in ipairs(meta[order_name] or vim.tbl_keys(meta[tbl_name])) do
      local row = meta[tbl_name][id]
      if row and id ~= item[field] then
        table.insert(list, { id = id, name = row.name or id })
      end
    end
    vim.ui.select(list, {
      prompt = ("%s %s is %s → "):format(key_of(bufnr), label:lower(), item[field] and meta[tbl_name][item[field]]
        and meta[tbl_name][item[field]].name or "?"),
      format_item = function(x)
        return x.name
      end,
    }, function(choice)
      if choice then
        items.update(ref, { [field] = choice.id },
          after(bufnr, ("%s: %s → %s"):format(key_of(bufnr), label:lower(), choice.name)))
      end
    end)
  end)
end

function M.pick_priority(bufnr)
  pick_field(bufnr, "priorities", "priority_order", "priority_id", "Priority")
end

function M.edit(bufnr)
  local item = last_item[bufnr]
  if item then
    require("sprints.ui.edit").edit(item, function()
      M.refresh_ref(item.ref)
    end)
  end
end

function M.comment(bufnr)
  require("sprints.ui.comment").open(ref_of(bufnr), key_of(bufnr), function()
    M.refresh(bufnr)
  end)
end

function M.open_in_browser(bufnr)
  local url = vim.b[bufnr].sprints_url
  if url then
    vim.ui.open(url)
  end
end

function M.yank_key(bufnr)
  util.yank(key_of(bufnr), "key")
end

function M.yank_url(bufnr)
  if vim.b[bufnr].sprints_url then
    util.yank(vim.b[bufnr].sprints_url, "link")
  end
end

function M.show_raw(bufnr)
  local item = last_item[bufnr]
  if item then
    M.show_value("sprints://raw/" .. item.ref.item, { details = item.raw_body, decoded_row = item.raw })
  end
end

function M.show_value(name, value)
  local raw_buf = util.named_scratch(name, "lua")
  util.set_lines(raw_buf, vim.split(vim.inspect(value), "\n", { plain = true }))
  util.show(raw_buf)
end

local ACTIONS = {
  { "status", M.change_status, "change status" },
  { "edit", M.edit, "edit title, description, fields (:w saves)" },
  { "comment", M.comment, "add a comment (:w posts)" },
  { "assign_me", M.toggle_me, "add / remove yourself as owner" },
  { "owners", M.pick_owner, "add / remove an owner" },
  { "unassign", M.unassign_all, "remove all owners (asks first)" },
  { "priority", M.pick_priority, "change priority" },
  { "yank_key", M.yank_key, "copy the item key" },
  { "yank_url", M.yank_url, "copy the link" },
  { "browser", M.open_in_browser, "open in browser" },
  { "raw", M.show_raw, "show the raw API response" },
  { "refresh", M.refresh, "refresh" },
  {
    "close",
    function(bufnr)
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end,
    "close",
  },
}

local function setup_keymaps(bufnr)
  local keys = (config.options.keymaps or {}).item or {}
  local help = { "sprints.nvim item buffer" }
  for _, a in ipairs(ACTIONS) do
    local name, fn, desc = a[1], a[2], a[3]
    if keys[name] then
      vim.keymap.set("n", keys[name], function()
        fn(bufnr)
      end, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: " .. desc })
      table.insert(help, ("  %-6s %s"):format(keys[name], desc))
    end
  end
  if keys.help then
    vim.keymap.set("n", keys.help, function()
      vim.notify(table.concat(help, "\n"))
    end, { buffer = bufnr, nowait = true, silent = true, desc = "Sprints: help" })
  end
end

function M.open(item, opts)
  util.setup_highlight_groups()
  local bufnr, created = util.named_scratch(buf_name(item.ref), "sprints-item")
  if created then
    if not pcall(vim.treesitter.start, bufnr, "markdown") then
      vim.bo[bufnr].syntax = "markdown"
    end
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      once = true,
      callback = function()
        last_item[bufnr] = nil
      end,
    })
  end
  render_into(bufnr, item)
  setup_keymaps(bufnr)
  util.show(bufnr, vim.tbl_extend("force", { role = "item" }, opts or {}))
  vim.wo.winbar = "%#sprintsKey# " .. (item.key or "") .. " %* s status · e edit · c comment · a me · o owners · g? more"
  return bufnr
end

function M.open_ref(ref, hint, opts)
  vim.notify("sprints.nvim: loading " .. (hint or ref.item) .. "…")
  items.get(ref, function(item, err)
    if not item then
      return util.notify_error("failed to fetch " .. (hint or ref.item), err)
    end
    M.open(item, opts)
  end)
end

return M
