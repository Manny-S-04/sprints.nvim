local config = require("sprints.config")
local util = require("sprints.ui.util")
local workspace = require("sprints.api.workspace")

local M = {}

local function choose(list, prompt, cb)
  if #list == 1 then
    return cb(list[1])
  end
  vim.ui.select(list, {
    prompt = prompt,
    format_item = function(x)
      return ("%s  [%s]"):format(x.name or "?", x.id)
    end,
  }, function(choice)
    if choice then
      cb(choice)
    end
  end)
end

function M.team(cb)
  local o = config.options
  if config.present(o.team_id) then
    return cb(tostring(o.team_id))
  end
  workspace.teams(function(teams, err)
    if not teams then
      return util.notify_error("could not list workspaces", err)
    end
    if #teams == 0 then
      return vim.notify("sprints.nvim: you're not in any Zoho Sprints workspace", vim.log.levels.WARN)
    end
    choose(teams, "Zoho Sprints workspace", function(t)
      o.team_id = t.id
      cb(t.id)
    end)
  end)
end

function M.project(cb, pick)
  M.team(function(team)
    local o = config.options
    if not pick and config.present(o.project_id) then
      return cb(team, tostring(o.project_id))
    end
    workspace.projects(team, function(projects, err)
      if not projects then
        return util.notify_error("could not list projects", err)
      end
      if #projects == 0 then
        return vim.notify("sprints.nvim: no projects visible to you", vim.log.levels.WARN)
      end
      choose(projects, "Zoho Sprints project", function(p)
        o.project_id = p.id
        cb(team, p.id)
      end)
    end)
  end)
end

return M
