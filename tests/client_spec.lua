local client = require("sprints.api.client")
local config = require("sprints.config")

describe("sprints.api.client", function()
  before_each(function()
    config.setup({ dc = "eu", client_id = "id", client_secret = "secret", refresh_token = "rt" })
  end)

  it("derives hosts from the data centre", function()
    assert.are.equal("https://sprintsapi.zoho.eu/zsapi", config.api_base())
    config.setup({ dc = "au" })
    assert.are.equal("https://accounts.zoho.com.au", config.accounts_base())
  end)

  it("builds sorted, encoded query strings; tables go as JSON", function()
    assert.are.equal("https://h/zsapi/teams/?action=data&f=%7B%22a%22%3A1%7D&index=1",
      client.build_url("https://h/zsapi/", "/teams/", { index = 1, action = "data", f = { a = 1 } }))
  end)

  it("keeps headers and form values out of argv", function()
    local cmd, stdin = client.build_command("POST", "https://h/x", {
      headers = { Authorization = "Zoho-oauthtoken SECRET" },
      form = { users = { "1" }, name = 'say "hi"' },
    })
    assert.is_nil(table.concat(cmd, " "):find("SECRET", 1, true))
    assert.truthy(stdin:find('header = "Authorization: Zoho-oauthtoken SECRET"', 1, true))
    assert.truthy(stdin:find('data-urlencode = "name=say \\"hi\\""', 1, true))
    assert.truthy(stdin:find('data-urlencode = "users=[\\"1\\"]"', 1, true))
  end)

  it("treats Zoho's HTTP-200 failures as errors", function()
    local _, err = client.parse_result({ code = 0, stdout = '{"status":"failed","code":7601,"message":"No permission"}\n__SPRINTS_NVIM_STATUS__200' })
    assert.are.equal("No permission", err.message)
    local _, oauth = client.parse_result({ code = 0, stdout = '{"error":"invalid_code"}\n__SPRINTS_NVIM_STATUS__200' })
    assert.are.equal("invalid_code", oauth.message)
    local ok = client.parse_result({ code = 0, stdout = '{"status":"success","x":1}\n__SPRINTS_NVIM_STATUS__200' })
    assert.are.equal(1, ok.body.x)
  end)

  it("reports curl failures and non-2xx", function()
    local _, e1 = client.parse_result({ code = 6, stderr = "could not resolve" })
    assert.are.equal("transport", e1.type)
    local _, e2 = client.parse_result({ code = 0, stdout = "\n__SPRINTS_NVIM_STATUS__500" })
    assert.are.equal(500, e2.status)
  end)
end)
