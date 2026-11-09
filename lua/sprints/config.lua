local M = {}

-- Zoho runs separate data centres; the account and API hosts differ per DC.
-- Use the suffix from your Sprints URL: sprints.zoho.eu -> "eu", sprints.zoho.com -> "com".
M.DATA_CENTRES = {
  com = "com",
  eu = "eu",
  uk = "uk",
  ["in"] = "in",
  au = "com.au",
  ["com.au"] = "com.au",
  jp = "jp",
  ca = "ca",
  sa = "sa",
  cn = "com.cn",
  ["com.cn"] = "com.cn",
}

local defaults = {
  -- Data centre suffix (see DATA_CENTRES). Env: ZOHO_DC.
  dc = "com",
  -- OAuth "Self Client" credentials from api-console.zoho.<dc>. Env: ZOHO_CLIENT_ID,
  -- ZOHO_CLIENT_SECRET, ZOHO_REFRESH_TOKEN. The refresh token never expires unless revoked;
  -- access tokens (1h) are minted from it on demand and only kept in memory.
  client_id = nil,
  client_secret = nil,
  refresh_token = nil,
  -- Workspace ("team") id, the zsoid. nil = the only team you're in, or pick one. Env: ZOHO_SPRINTS_TEAM.
  team_id = nil,
  -- Project the commands open by default. nil = pick from a list. Env: ZOHO_SPRINTS_PROJECT.
  project_id = nil,
  -- Your Sprints user id. nil = looked up by `email` in the workspace users. Env: ZOHO_SPRINTS_USER.
  user_id = nil,
  -- Used only to find user_id when it isn't set. Env: ZOHO_EMAIL.
  email = nil,
  -- Override the hosts derived from dc (proxies, a local mock server). Env: ZOHO_SPRINTS_API_URL,
  -- ZOHO_ACCOUNTS_URL. api_url includes the /zsapi prefix.
  api_url = nil,
  accounts_url = nil,
  -- request timeout in milliseconds
  timeout = 10000,
  -- page size for list endpoints (Zoho caps `range` at 100 on most of them)
  page_size = 100,
  -- Web link for an item. Placeholders: {dc} {team} {project} {sprint} {item} {no}.
  -- Check it against the address bar when you open an item in the browser and adjust.
  item_url = "https://sprints.zoho.{dc}/team/{team}#itemdetails/P{project}/I{item}",
  -- How item/list buffers are opened: "split", "vsplit", "tabnew" or "edit".
  open_cmd = "split",
  keymaps = {
    item = {
      close = "q",
      refresh = "r",
      status = "s",
      edit = "e",
      comment = "c",
      assign_me = "a",
      owners = "o",
      unassign = "A",
      priority = "p",
      yank_key = "yk",
      yank_url = "yu",
      browser = "gx",
      raw = "gR",
      help = "g?",
    },
    list = {
      open = "<CR>",
      new = "n",
      board = "b",
      mine = "m",
      yank_key = "yk",
      yank_url = "yu",
      browser = "gx",
      refresh = "r",
      close = "q",
      help = "g?",
    },
  },
}

M.options = vim.deepcopy(defaults)

local function env()
  return {
    dc = os.getenv("ZOHO_DC"),
    client_id = os.getenv("ZOHO_CLIENT_ID"),
    client_secret = os.getenv("ZOHO_CLIENT_SECRET"),
    refresh_token = os.getenv("ZOHO_REFRESH_TOKEN"),
    team_id = os.getenv("ZOHO_SPRINTS_TEAM"),
    project_id = os.getenv("ZOHO_SPRINTS_PROJECT"),
    user_id = os.getenv("ZOHO_SPRINTS_USER"),
    email = os.getenv("ZOHO_EMAIL"),
    api_url = os.getenv("ZOHO_SPRINTS_API_URL"),
    accounts_url = os.getenv("ZOHO_ACCOUNTS_URL"),
  }
end

local function present(v)
  return v ~= nil and v ~= ""
end
M.present = present

--- Merge defaults <- environment <- explicit opts (explicit wins).
--- Missing credentials don't warn here, so machines without Zoho access start silently.
function M.setup(opts)
  local from_env = {}
  for k, v in pairs(env()) do
    if present(v) then
      from_env[k] = v
    end
  end
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), from_env, opts or {})
  -- New credentials / project: tokens and lookups cached for the old ones are stale.
  -- (pcall: clearing a cache must never be what breaks setup.)
  pcall(function()
    require("sprints.api.auth").invalidate()
    require("sprints.api.workspace").clear_cache()
  end)
  return M.options
end

--- Domain suffix for the configured data centre ("eu", "com.au", ...).
function M.domain()
  local dc = tostring(M.options.dc or "com"):lower():gsub("^%.", "")
  return M.DATA_CENTRES[dc] or dc
end

function M.api_base()
  return M.options.api_url or ("https://sprintsapi.zoho.%s/zsapi"):format(M.domain())
end

function M.accounts_base()
  return M.options.accounts_url or ("https://accounts.zoho.%s"):format(M.domain())
end

local function missing()
  local o, out = M.options, {}
  for _, k in ipairs({ "client_id", "client_secret", "refresh_token" }) do
    if not present(o[k]) then
      table.insert(out, ("%s (ZOHO_%s)"):format(k, k:upper()))
    end
  end
  return out
end

function M.is_configured()
  return #missing() == 0
end

--- WARN (not ERROR: an error inside a lazy-loaded command becomes a stack trace).
function M.validate()
  local m = missing()
  if #m > 0 then
    vim.notify("sprints.nvim: missing configuration: " .. table.concat(m, ", ") .. " (see :help sprints-setup)",
      vim.log.levels.WARN)
    return false
  end
  return true
end

return M
