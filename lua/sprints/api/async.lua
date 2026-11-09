local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")

local M = {}

function M.all(fns, cb)
  local n, results, failed = #fns, {}, false
  if n == 0 then
    return vim.schedule(function()
      cb({}, nil)
    end)
  end
  local remaining = n
  for i, fn in ipairs(fns) do
    fn(function(value, err)
      if failed then
        return
      end
      if err then
        failed = true
        return cb(nil, err)
      end
      results[i] = value
      remaining = remaining - 1
      if remaining == 0 then
        cb(results, nil)
      end
    end)
  end
end

function M.fail(cb, message, type)
  vim.schedule(function()
    cb(nil, { message = message, type = type or "validation" })
  end)
end

function M.ok(cb, value)
  vim.schedule(function()
    cb(value, nil)
  end)
end

---@param path string
---@param query table extra query params (action etc.)
---@param prefix string resource prefix used to count rows on a page
---@param cb fun(bodies: table[]|nil, err: table|nil)
function M.pages(path, query, prefix, cb)
  local size = config.options.page_size or 100
  local bodies, seen, total = {}, {}, 0
  local MAX_ROWS = 2000

  local function page(index)
    local q = vim.tbl_extend("force", {}, query or {}, { index = index, range = size })
    client.request("GET", path, { query = q }, function(result, err)
      if not result then
        return cb(nil, err)
      end
      local body = result.body or {}
      local rows = decode.rows(body, prefix)
      local fresh = 0
      for _, r in ipairs(rows) do
        if not seen[r.id] then
          seen[r.id], fresh = true, fresh + 1
        end
      end
      if fresh == 0 then
        if #bodies == 0 then
          table.insert(bodies, body)
        end
        return cb(bodies, nil)
      end
      table.insert(bodies, body)
      total = total + fresh
      if total >= MAX_ROWS then
        return cb(bodies, nil)
      end
      page(index + #rows)
    end)
  end
  page(1)
end

function M.merge(bodies, prefix)
  local rows, side, seen = {}, {}, {}
  for _, body in ipairs(bodies) do
    for _, r in ipairs(decode.rows(body, prefix)) do
      if not seen[r.id] then
        seen[r.id] = true
        table.insert(rows, r)
      end
    end
    for k in pairs(body) do
      local other = type(k) == "string" and k:match("^(.-)JObj$")
      if other and other ~= prefix then
        side[other] = side[other] or {}
        for id, row in pairs(decode.by_id(body, other)) do
          side[other][id] = row
        end
      end
    end
  end
  return rows, side
end

return M
