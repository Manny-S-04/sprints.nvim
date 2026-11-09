local config = require("sprints.config")

local M = {}

function M.uri_encode(str)
  return (tostring(str):gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

local function stringify(v)
  if type(v) == "table" then
    return vim.json.encode(v)
  end
  return tostring(v)
end
M.stringify = stringify

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

function M.build_url(base, path, query)
  if not base or base == "" then
    error("sprints.nvim: API base url is not configured")
  end
  local url = base:gsub("/+$", "") .. (path:match("^/") and path or ("/" .. path))
  if query and next(query) ~= nil then
    local parts = {}
    for _, k in ipairs(sorted_keys(query)) do
      table.insert(parts, M.uri_encode(k) .. "=" .. M.uri_encode(stringify(query[k])))
    end
    url = url .. "?" .. table.concat(parts, "&")
  end
  return url
end

local function curl_quote(s)
  s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. s .. '"'
end

local STATUS_MARKER = "\n__SPRINTS_NVIM_STATUS__"

---@param method string
---@param url string full url, query included
---@param opts { headers: table|nil, form: table|nil }
function M.build_command(method, url, opts)
  local cmd = {
    "curl",
    "-sS",
    "-X",
    method,
    "--max-time",
    tostring(math.max(1, math.floor((config.options.timeout or 10000) / 1000))),
    "-w",
    STATUS_MARKER .. "%{http_code}",
    "--config",
    "-",
    url,
  }
  local stdin = {}
  for _, k in ipairs(sorted_keys(opts.headers or {})) do
    table.insert(stdin, "header = " .. curl_quote(k .. ": " .. opts.headers[k]))
  end
  table.insert(stdin, "header = " .. curl_quote("Accept: application/json"))
  if opts.form then
    for _, k in ipairs(sorted_keys(opts.form)) do
      table.insert(stdin, "data-urlencode = " .. curl_quote(k .. "=" .. stringify(opts.form[k])))
    end
  end
  return cmd, table.concat(stdin, "\n") .. "\n"
end

function M.error_in_body(decoded)
  if type(decoded) ~= "table" then
    return nil
  end
  if type(decoded.error) == "string" then
    return decoded.error
  end
  if type(decoded.error) == "table" and decoded.error.message then
    return tostring(decoded.error.message)
  end
  local status = type(decoded.status) == "string" and decoded.status:lower() or nil
  if status == "failed" or status == "failure" or status == "error" then
    return tostring(decoded.message or decoded.code or "request failed")
  end
  return nil
end

local function quote_segment(seg)
  return (seg:gsub("()(%-?%d+)()", function(s, digits, e)
    local before, after = seg:sub(s - 1, s - 1), seg:sub(e, e)
    if #digits:gsub("^%-", "") < 16 or before:match("[%w%.]") or after:match("[%.eE%w]") then
      return nil
    end
    return '"' .. digits .. '"'
  end))
end

function M.quote_big_ints(json)
  if not json:find("%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d") then
    return json
  end
  local out, i, n = {}, 1, #json
  while i <= n do
    local q = json:find('"', i, true)
    table.insert(out, quote_segment(json:sub(i, (q or n + 1) - 1)))
    if not q then
      break
    end
    local j = q + 1
    while true do
      local e = json:find('["\\]', j)
      if not e then
        j = n + 1
        break
      end
      if json:sub(e, e) == "\\" then
        j = e + 2
      else
        j = e + 1
        break
      end
    end
    table.insert(out, json:sub(q, j - 1))
    i = j
  end
  return table.concat(out)
end

local CURL_ERRORS = {
  [6] = "can't resolve the Zoho host (offline, or wrong dc?)",
  [7] = "can't connect to Zoho (offline or blocked?)",
  [28] = "Zoho didn't answer in time (raise `timeout`?)",
  [35] = "TLS handshake with Zoho failed (proxy intercepting?)",
  [60] = "Zoho's certificate isn't trusted (corporate proxy? set CURL_CA_BUNDLE)",
}

function M.parse_result(sys_result)
  if sys_result.code ~= 0 then
    local known = CURL_ERRORS[sys_result.code]
    local stderr = sys_result.stderr and vim.trim(sys_result.stderr) or ""
    return nil, {
      message = known or ("curl failed (exit %d)%s"):format(sys_result.code, stderr ~= "" and (": " .. stderr) or ""),
      type = "transport",
      detail = stderr,
    }
  end
  local body, status_str = (sys_result.stdout or ""):match("^(.*)" .. STATUS_MARKER .. "(%d+)%s*$")
  if not body then
    return nil, { message = "could not parse HTTP response from curl", type = "transport" }
  end
  local status = tonumber(status_str)
  local decoded = nil
  if body ~= "" then
    local ok, v = pcall(vim.json.decode, M.quote_big_ints(body), { luanil = { object = true, array = true } })
    if ok then
      decoded = v
    end
  end

  local body_err = M.error_in_body(decoded)
  if status < 200 or status >= 300 or body_err then
    local msg = body_err or (#body < 300 and body ~= "" and body) or ("HTTP " .. status)
    return nil, { message = msg, status = status, type = "http", body = decoded }
  end
  return { status = status, body = decoded }, nil
end

---@param method string
---@param url string
---@param opts { headers: table|nil, form: table|nil }|nil
---@param cb fun(result: table|nil, err: table|nil)
function M.raw(method, url, opts, cb)
  local cmd, stdin = M.build_command(method, url, opts or {})
  local ok, err = pcall(vim.system, cmd, { text = true, stdin = stdin }, function(sys_result)
    local result, req_err = M.parse_result(sys_result)
    vim.schedule(function()
      cb(result, req_err)
    end)
  end)
  if not ok then
    vim.schedule(function()
      cb(nil, { message = "failed to run curl - is it on $PATH? (" .. tostring(err) .. ")", type = "transport" })
    end)
  end
end

local function is_auth_failure(err)
  if not err then
    return false
  end
  if err.status == 401 then
    return true
  end
  local msg = (err.message or ""):lower()
  return msg:find("invalid_oauth", 1, true) ~= nil
    or msg:find("invalid oauth", 1, true) ~= nil
    or msg:find("oauth token", 1, true) ~= nil
end

---@param method string
---@param path string relative to /zsapi, e.g. "/teams/"
---@param opts { query: table|nil, form: table|nil }|nil
---@param cb fun(result: table|nil, err: table|nil)
function M.request(method, path, opts, cb)
  opts = opts or {}
  local auth = require("sprints.api.auth")
  local ok, url = pcall(M.build_url, config.api_base(), path, opts.query)
  if not ok then
    return vim.schedule(function()
      cb(nil, { message = tostring(url), type = "config" })
    end)
  end

  local function attempt(retried)
    auth.token(function(token, terr)
      if not token then
        return cb(nil, terr)
      end
      M.raw(method, url, { headers = { Authorization = "Zoho-oauthtoken " .. token }, form = opts.form },
        function(result, err)
          if not result and not retried and is_auth_failure(err) then
            auth.invalidate()
            return attempt(true)
          end
          cb(result, err)
        end)
    end)
  end
  attempt(false)
end

return M
