local M = {}

local function prop_map(body, prefix)
  for _, k in ipairs({ prefix .. "_prop", prefix .. "prop", prefix .. "Prop", prefix .. "_props", prefix .. "Props" }) do
    if type(body[k]) == "table" then
      return body[k]
    end
  end
  return nil
end

local function ordered_ids(body, prefix, jobj)
  local out, used = {}, {}
  local ids = body[prefix .. "Ids"] or body[prefix .. "ids"]
  if type(ids) == "table" then
    for _, id in ipairs(ids) do
      local k = tostring(id)
      if jobj[k] ~= nil and not used[k] then
        used[k] = true
        table.insert(out, k)
      end
    end
  end
  local rest = {}
  for id in pairs(jobj) do
    if not used[id] then
      table.insert(rest, id)
    end
  end
  table.sort(rest)
  return vim.list_extend(out, rest)
end

local function name_row(id, values, props)
  local row = { id = id }
  if type(values) ~= "table" then
    row.name = values
    return row
  end
  if props then
    for field, idx in pairs(props) do
      local i = tonumber(idx)
      if i then
        row[field] = values[i + 1]
      end
    end
  end
  if row.name == nil and type(values[1]) ~= "table" then
    row.name = values[1]
  end
  row.id = id
  return row
end

function M.rows(body, prefix)
  if type(body) ~= "table" then
    return {}
  end
  local jobj = body[prefix .. "JObj"] or body[prefix .. "jobj"]
  if type(jobj) ~= "table" then
    return {}
  end
  local props = prop_map(body, prefix)
  local out = {}
  for _, id in ipairs(ordered_ids(body, prefix, jobj)) do
    table.insert(out, name_row(id, jobj[id], props))
  end
  return out
end

function M.by_id(body, prefix)
  local out = {}
  for _, row in ipairs(M.rows(body, prefix)) do
    out[row.id] = row
  end
  return out
end

function M.pick(row, names)
  for _, n in ipairs(names) do
    local v = row[n]
    if v ~= nil and v ~= "" and v ~= vim.NIL then
      return v
    end
  end
  return nil
end

function M.id_list(v)
  if v == nil or v == "" or v == vim.NIL then
    return {}
  end
  if type(v) == "table" then
    local out = {}
    for _, x in ipairs(v) do
      table.insert(out, tostring(x))
    end
    return out
  end
  local s = tostring(v)
  if s:match("^%s*%[") then
    local ok, decoded = pcall(vim.json.decode, s)
    if ok and type(decoded) == "table" then
      return M.id_list(decoded)
    end
  end
  local out = {}
  for part in s:gmatch("[^,%s]+") do
    table.insert(out, part)
  end
  return out
end

return M
