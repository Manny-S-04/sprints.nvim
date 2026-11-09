local config = require("sprints.config")

local M = {}

local cached = nil
local waiting = nil

local EARLY_SECONDS = 60

function M.invalidate()
  cached = nil
end

function M.lifetime_seconds(body)
  local s = tonumber(body.expires_in_sec)
  if not s then
    s = tonumber(body.expires_in) or 3600
    if s > 86400 then
      s = s / 1000
    end
  end
  return math.min(s, 3600)
end

local function flush(token, err)
  local queue = waiting or {}
  waiting = nil
  for _, cb in ipairs(queue) do
    cb(token, err)
  end
end

---@param cb fun(token: string|nil, err: table|nil)
function M.token(cb)
  if cached and os.time() < cached.expires_at then
    return vim.schedule(function()
      cb(cached.token, nil)
    end)
  end
  if waiting then
    return table.insert(waiting, cb)
  end
  if not config.is_configured() then
    return vim.schedule(function()
      cb(nil, { message = "OAuth credentials missing (ZOHO_CLIENT_ID / ZOHO_CLIENT_SECRET / ZOHO_REFRESH_TOKEN)",
        type = "auth" })
    end)
  end

  waiting = { cb }
  local o = config.options
  require("sprints.api.client").raw("POST", config.accounts_base() .. "/oauth/v2/token", {
    form = {
      grant_type = "refresh_token",
      refresh_token = o.refresh_token,
      client_id = o.client_id,
      client_secret = o.client_secret,
    },
  }, function(result, err)
    local body = result and result.body or nil
    if not body or type(body.access_token) ~= "string" then
      local msg = err and err.message or "no access_token in the token response"
      if msg == "invalid_code" then
        msg = "invalid_code: the refresh token was revoked or belongs to another data centre (check dc)"
      elseif msg == "invalid_client" then
        msg = "invalid_client: client id/secret wrong, or a different data centre (check dc)"
      end
      return flush(nil, { message = "token refresh failed: " .. msg, type = "auth" })
    end
    cached = {
      token = body.access_token,
      expires_at = os.time() + math.max(0, M.lifetime_seconds(body) - EARLY_SECONDS),
    }
    flush(cached.token, nil)
  end)
end

return M
