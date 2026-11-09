local config = require("sprints.config")

local M = {}

local function api(name)
  return require("sprints.api." .. name)
end

local function notify_error(prefix, err)
  require("sprints.ui.util").notify_error(prefix, err)
end

local function items_of(team, project, sprint_ids, mine_only, cb)
  local async = api("async")
  local function run(me)
    local fns = {}
    for _, sid in ipairs(sprint_ids) do
      table.insert(fns, function(done)
        local ref = { team = team, project = project, sprint = sid }
        if me then
          api("items").list_owned(ref, me, done)
        else
          api("items").list(ref, done)
        end
      end)
    end
    async.all(fns, function(lists, err)
      if not lists then
        return cb(nil, err)
      end
      local out = {}
      for _, l in ipairs(lists) do
        vim.list_extend(out, l)
      end
      cb(out, nil)
    end)
  end
  if not mine_only then
    return run(nil)
  end
  api("workspace").me(team, project, function(me, err)
    if not me then
      return cb(nil, err)
    end
    run(me)
  end)
end

local function active_fetcher(team, project, on_sprints)
  return function(mine_only, cb)
    api("sprints").active(team, project, function(active, err)
      if not active then
        return cb(nil, err)
      end
      if #active == 0 then
        return cb(nil, { message = "no active sprint in this project (try :SprintsSprint pick)" })
      end
      local ids, names = {}, {}
      for _, s in ipairs(active) do
        table.insert(ids, s.id)
        table.insert(names, s.name)
      end
      on_sprints(active)
      items_of(team, project, ids, mine_only, function(list, ierr)
        cb(list, ierr, table.concat(names, " + "))
      end)
    end)
  end
end

---@param opts { mine_only: boolean|nil, group: boolean|nil }
local function open_active(opts)
  require("sprints.ui.context").project(function(team, project)
    local first_active = nil
    require("sprints.ui.list").open_with("active/" .. project, "Active sprint",
      active_fetcher(team, project, function(active)
        first_active = active[1]
      end), {
        mine_only = opts.mine_only,
        group = opts.group,
        project = { team = team, project = project },
        new_target = function()
          return first_active
            and { team = team, project = project, sprint = first_active.id, sprint_name = first_active.name }
        end,
      })
  end)
end

local function open_sprint(team, project, sprint)
  require("sprints.ui.list").open_with("sprint/" .. sprint.id, sprint.name, function(mine_only, cb)
    items_of(team, project, { sprint.id }, mine_only, cb)
  end, {
    project = { team = team, project = project },
    new_target = { team = team, project = project, sprint = sprint.id, sprint_name = sprint.name },
  })
end

local function cmd_sprint(cmd_opts)
  local arg = vim.trim(cmd_opts.args or "")
  if arg == "" then
    return open_active({})
  end
  if arg ~= "pick" then
    return vim.notify("sprints.nvim: usage :SprintsSprint [pick]", vim.log.levels.WARN)
  end
  require("sprints.ui.context").project(function(team, project)
    api("sprints").list(team, project, function(list, err)
      if not list then
        return notify_error("could not list sprints", err)
      end
      if #list == 0 then
        return vim.notify("sprints.nvim: this project has no sprints", vim.log.levels.WARN)
      end
      vim.ui.select(list, {
        prompt = "Sprint",
        format_item = function(s)
          return ("%s  [%s]"):format(s.name, s.state or "?")
        end,
      }, function(choice)
        if choice then
          open_sprint(team, project, choice)
        end
      end)
    end)
  end)
end

local function cmd_backlog()
  require("sprints.ui.context").project(function(team, project)
    api("sprints").backlog_id(team, project, function(id, err)
      if not id then
        return notify_error("could not find the backlog", err)
      end
      open_sprint(team, project, { id = id, name = "Backlog" })
    end)
  end)
end

local function scan(team, project, cb)
  local async = api("async")
  async.all({
    function(done)
      api("sprints").active(team, project, done)
    end,
    function(done)
      api("sprints").backlog_id(team, project, function(id)
        done(id or false, nil)
      end)
    end,
  }, function(res, err)
    if not res then
      return cb(nil, err)
    end
    local ids = {}
    for _, s in ipairs(res[1]) do
      table.insert(ids, s.id)
    end
    if res[2] then
      table.insert(ids, res[2])
    end
    items_of(team, project, ids, false, cb)
  end)
end

function M.item_contains(it, query)
  local hay = ((it.summary or "") .. " " .. (it.key or "")):lower()
  for word in query:lower():gmatch("%S+") do
    if not hay:find(word, 1, true) then
      return false
    end
  end
  return true
end

local function cmd_search(cmd_opts)
  local query = vim.trim(cmd_opts.args or "")
  if query == "" then
    return vim.notify("sprints.nvim: usage :SprintsSearch <words>", vim.log.levels.WARN)
  end
  require("sprints.ui.context").project(function(team, project)
    require("sprints.ui.list").open_with("search/" .. project, ("Search: %s"):format(query), function(mine_only, cb)
      scan(team, project, function(list, err)
        if not list then
          return cb(nil, err)
        end
        local hits = vim.tbl_filter(function(it)
          return M.item_contains(it, query)
        end, list)
        if mine_only then
          api("workspace").me(team, project, function(me, merr)
            if not me then
              return cb(nil, merr)
            end
            cb(vim.tbl_filter(function(it)
              return vim.tbl_contains(it.owner_ids, me)
            end, hits), nil)
          end)
        else
          cb(hits, nil)
        end
      end)
    end, { project = { team = team, project = project } })
  end)
end

local function cmd_new()
  require("sprints.ui.context").project(function(team, project)
    api("sprints").active(team, project, function(active)
      local function go(target)
        require("sprints.ui.edit").new(target, function(new_ref)
          require("sprints.ui.list").refresh_all()
          if new_ref.item then
            require("sprints.ui.item").open_ref(new_ref, "the new item")
          end
        end)
      end
      if active and active[1] then
        return go({ team = team, project = project, sprint = active[1].id, sprint_name = active[1].name })
      end
      api("sprints").backlog_id(team, project, function(id, err)
        if not id then
          return notify_error("no active sprint or backlog to create in", err)
        end
        go({ team = team, project = project, sprint = id, sprint_name = "Backlog" })
      end)
    end)
  end)
end

function M.ref_in_word(word)
  return word:match("[%w%-]*%d+")
end

function M.item_matches(it, wanted)
  local w = wanted:upper():gsub("^#", "")
  local key, no = (it.key or ""):upper(), tostring(it.no or ""):upper()
  if w == key or w == no then
    return true
  end
  if w:match("^%d+$") then
    return key:match("(%d+)$") == w or no:match("(%d+)$") == w
  end
  local function ends_with(s, tail)
    return tail ~= "" and s:match("%-" .. vim.pesc(tail) .. "$") ~= nil
  end
  return ends_with(key, w) or ends_with(no, w) or ends_with(w, key) or ends_with(w, no)
end

local function cmd_item(cmd_opts)
  local wanted = vim.trim(cmd_opts.args or "")
  if wanted == "" then
    wanted = M.ref_in_word(vim.fn.expand("<cWORD>")) or ""
  end
  if wanted == "" then
    return vim.notify("sprints.nvim: usage :SprintsItem <item number> (or cursor on one)", vim.log.levels.WARN)
  end
  require("sprints.ui.context").project(function(team, project)
    vim.notify("sprints.nvim: looking for " .. wanted .. "…")
    scan(team, project, function(list, err)
      if not list then
        return notify_error("could not search", err)
      end
      for _, it in ipairs(list) do
        if M.item_matches(it, wanted) then
          return require("sprints.ui.item").open_ref(it.ref, it.key)
        end
      end
      vim.notify(("sprints.nvim: %s not found in the active sprint(s) or backlog (try :SprintsSearch)"):format(wanted),
        vim.log.levels.WARN)
    end)
  end)
end

local RAW = {
  teams = function(_, _, cb)
    api("client").request("GET", "/teams/", {}, cb)
  end,
  projects = function(team, _, cb)
    api("client").request("GET", ("/team/%s/projects/"):format(team), { query = { action = "allprojects", index = 1, range = 10 } }, cb)
  end,
  project = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/"):format(team, project), { query = { action = "details" } }, cb)
  end,
  sprints = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/sprints/"):format(team, project), { query = { action = "data", index = 1, range = 10 } }, cb)
  end,
  statuses = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/itemstatus/"):format(team, project), { query = { action = "data" } }, cb)
  end,
  users = function(team, project, cb)
    api("client").request("GET", ("/team/%s/projects/%s/users/"):format(team, project), { query = { action = "data", index = 1, range = 10 } }, cb)
  end,
}

local function cmd_raw(cmd_opts)
  local what = vim.trim(cmd_opts.args or "")
  local fn = RAW[what]
  if not fn then
    return vim.notify("sprints.nvim: usage :SprintsRaw " .. table.concat(vim.tbl_keys(RAW), "|"), vim.log.levels.WARN)
  end
  local function go(team, project)
    fn(team, project, function(result, err)
      require("sprints.ui.item").show_value("sprints://raw/" .. what, result and result.body or { error = err })
    end)
  end
  if what == "teams" then
    return go(nil, nil)
  end
  require("sprints.ui.context").project(go)
end

local function cmd_help()
  local o = config.options
  vim.notify(table.concat({
    "sprints.nvim (Zoho Sprints)",
    "",
    "  :SprintsMine            Your items in the active sprint(s)",
    "  :SprintsBoard           Active sprint(s) grouped by status",
    "  :SprintsNew             New item (in the active sprint; :w creates)",
    "  :SprintsSearch WORDS    Items whose title has all the words (active sprint + backlog)",
    "  :SprintsSprint [pick]   Active sprint(s); pick = choose any sprint",
    "  :SprintsBacklog         The project backlog",
    "  :SprintsItem [NO]       Open an item by number (defaults to the word under the cursor)",
    "  :SprintsProject         Switch project for this session",
    "  :SprintsRefresh         Refresh the current item buffer",
    "  :SprintsRaw <what>      Raw API response (teams|projects|project|sprints|statuses|users)",
    "",
    "In a list or an item, g? shows its keys.",
    "",
    ("Data centre: zoho.%s   team: %s   project: %s"):format(config.domain(), o.team_id or "(pick)", o.project_id or "(pick)"),
  }, "\n"))
end

local function guarded(fn)
  return function(cmd_opts)
    if config.validate() then
      fn(cmd_opts or {})
    end
  end
end

local COMMANDS = {
  { "Sprints", cmd_help, { nargs = 0, desc = "sprints.nvim help" }, false },
  { "SprintsMine", function() open_active({ mine_only = true }) end, { nargs = 0, desc = "Your items in the active sprint" } },
  { "SprintsBoard", function() open_active({ group = true }) end, { nargs = 0, desc = "Active sprint grouped by status" } },
  { "SprintsNew", cmd_new, { nargs = 0, desc = "Create a Zoho Sprints item (:w creates)" } },
  { "SprintsSearch", cmd_search, { nargs = "+", desc = "Find items by title words in the active sprint and backlog" } },
  { "SprintsSprint", cmd_sprint, {
    nargs = "?",
    complete = function()
      return { "pick" }
    end,
    desc = "Items in the active sprint (or pick one)",
  } },
  { "SprintsBacklog", cmd_backlog, { nargs = 0, desc = "Items in the project backlog" } },
  { "SprintsItem", cmd_item, { nargs = "?", desc = "Open a Zoho Sprints item by number" } },
  { "SprintsProject", function()
    require("sprints.ui.context").project(function(_, project)
      vim.notify("sprints.nvim: project " .. project .. " for this session")
    end, true)
  end, { nargs = 0, desc = "Switch Zoho Sprints project" } },
  { "SprintsRefresh", function()
    require("sprints.ui.item").refresh(vim.api.nvim_get_current_buf())
  end, { nargs = 0, desc = "Refresh the current item buffer" } },
  { "SprintsRaw", cmd_raw, {
    nargs = 1,
    complete = function()
      return vim.tbl_keys(RAW)
    end,
    desc = "Show a raw Zoho Sprints API response",
  } },
}
M.NAMES = vim.tbl_map(function(c)
  return c[1]
end, COMMANDS)

function M.setup()
  for _, c in ipairs(COMMANDS) do
    local fn = c[4] == false and c[2] or guarded(c[2])
    vim.api.nvim_create_user_command(c[1], fn, c[3])
  end
end

return M
