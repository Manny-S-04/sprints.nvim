local async = require("sprints.api.async")
local client = require("sprints.api.client")
local decode = require("sprints.api.decode")

local M = {}

M.SPRINT_TYPES = { ["1"] = "upcoming", ["2"] = "active", ["3"] = "completed", ["4"] = "cancelled" }

function M.state_of(row)
  local t = decode.pick(row, { "sprintType", "sprinttype", "type", "sprintStatus", "status" })
  if t == nil then
    return nil
  end
  local s = tostring(t)
  if M.SPRINT_TYPES[s] then
    return M.SPRINT_TYPES[s]
  end
  s = vim.trim(s:lower())
  local ALIASES = {
    upcoming = "upcoming",
    active = "active",
    ["in progress"] = "active",
    inprogress = "active",
    started = "active",
    running = "active",
    completed = "completed",
    complete = "completed",
    closed = "completed",
    cancelled = "cancelled",
    canceled = "cancelled",
  }
  return ALIASES[s] or s
end

function M.normalise(row)
  return {
    id = row.id,
    name = decode.pick(row, { "sprintName", "name" }) or row.id,
    no = decode.pick(row, { "sprintNo", "sprintno" }),
    state = M.state_of(row),
    start_date = decode.pick(row, { "startDate", "startdate", "sprintStartDate" }),
    end_date = decode.pick(row, { "endDate", "enddate", "sprintEndDate" }),
    raw = row,
  }
end

local names = {}
local backlog_cache = {}

function M.name_of(team, project, sprint_id)
  if sprint_id == nil then
    return nil
  end
  local key = team .. "/" .. project
  if backlog_cache[key] == tostring(sprint_id) then
    return "Backlog"
  end
  return (names[key] or {})[tostring(sprint_id)]
end

local STATE_RANK = { active = 1, upcoming = 2, completed = 3, cancelled = 4 }

function M.sort(list)
  table.sort(list, function(a, b)
    local ra, rb = STATE_RANK[a.state] or 5, STATE_RANK[b.state] or 5
    if ra ~= rb then
      return ra < rb
    end
    local na, nb = tonumber(a.no), tonumber(b.no)
    if na and nb and na ~= nb then
      return na > nb
    end
    return (a.name or "") > (b.name or "")
  end)
  return list
end

function M.list(team, project, cb)
  async.pages(("/team/%s/projects/%s/sprints/"):format(team, project), { action = "data" }, "sprint",
    function(bodies, err)
      if not bodies then
        return cb(nil, err)
      end
      local out, key = {}, team .. "/" .. project
      names[key] = names[key] or {}
      for _, r in ipairs((async.merge(bodies, "sprint"))) do
        local s = M.normalise(r)
        names[key][s.id] = s.name
        table.insert(out, s)
      end
      cb(M.sort(out), nil)
    end)
end

function M.active(team, project, cb)
  M.list(team, project, function(list, err)
    if not list then
      return cb(nil, err)
    end
    cb(vim.tbl_filter(function(s)
      return s.state == "active"
    end, list), nil)
  end)
end

local function find_key(t, wanted, depth)
  if type(t) ~= "table" or depth > 6 then
    return nil
  end
  for k, v in pairs(t) do
    if type(k) == "string" and k:lower() == wanted and (type(v) == "string" or type(v) == "number") then
      return tostring(v)
    end
  end
  for k, v in pairs(t) do
    if not (type(k) == "string" and k:lower():match("_?props?$")) then
      local found = find_key(v, wanted, depth + 1)
      if found then
        return found
      end
    end
  end
  return nil
end
M._find_key = find_key

function M.backlog_from_details(body, project)
  for _, row in ipairs(decode.rows(body, "project")) do
    if row.id == tostring(project) or #decode.rows(body, "project") == 1 then
      local id = decode.pick(row, { "backlogId", "backlogid", "backLogId" })
      if id then
        return tostring(id)
      end
    end
  end
  return find_key(body, "backlogid", 0)
end

function M.backlog_id(team, project, cb)
  local key = team .. "/" .. project
  if backlog_cache[key] then
    return async.ok(cb, backlog_cache[key])
  end
  client.request("GET", ("/team/%s/projects/%s/"):format(team, project), { query = { action = "details" } },
    function(result, err)
      if not result then
        return cb(nil, err)
      end
      local id = M.backlog_from_details(result.body, project)
      if not id then
        return cb(nil, { message = "project details have no backlogId (see :SprintsRaw project)", type = "api" })
      end
      backlog_cache[key] = id
      cb(id, nil)
    end)
end

return M
