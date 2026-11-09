local M = {}

function M.check()
  local health = vim.health
  local config = require("sprints.config")
  local o = config.options

  health.start("sprints.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10+ required (vim.system, vim.ui.open)")
  end
  if vim.fn.executable("curl") == 1 then
    health.ok("curl found")
  else
    health.error("curl not found on $PATH")
  end

  health.start("Configuration")
  health.info(("Data centre: zoho.%s (API %s)"):format(config.domain(), config.api_base()))
  for _, k in ipairs({ "client_id", "client_secret", "refresh_token" }) do
    if config.present(o[k]) then
      health.ok(k .. " is set")
    else
      health.warn(k .. " is not set (ZOHO_" .. k:upper() .. ")")
    end
  end
  for _, k in ipairs({ "team_id", "project_id" }) do
    if config.present(o[k]) then
      health.ok(k .. " = " .. tostring(o[k]))
    else
      health.info(k .. " not set: you'll be asked to pick")
    end
  end
  if config.present(o.user_id) then
    health.ok("user_id = " .. tostring(o.user_id))
  elseif config.present(o.email) then
    health.info("user_id will be looked up from email " .. o.email)
  else
    health.warn("neither user_id nor email set: :SprintsMine and assign-to-me won't work")
  end

  if not config.is_configured() then
    return
  end
  health.start("Connection")
  local done, token_err = false, nil
  require("sprints.api.auth").token(function(token, err)
    done, token_err = true, (not token) and err or nil
  end)
  vim.wait(o.timeout or 10000, function()
    return done
  end, 50)
  if not done then
    health.error("token request timed out")
  elseif token_err then
    health.error(token_err.message)
  else
    health.ok("OAuth token refresh works")
  end
end

return M
