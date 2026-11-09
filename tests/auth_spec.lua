local auth = require("sprints.api.auth")
local client = require("sprints.api.client")
local config = require("sprints.config")

local function await(fn)
  local done, a, b = false, nil, nil
  fn(function(x, y)
    done, a, b = true, x, y
  end)
  vim.wait(1000, function()
    return done
  end, 5)
  assert.is_true(done, "callback never ran")
  return a, b
end

describe("sprints.api.auth + client.request", function()
  local original_raw
  local calls

  before_each(function()
    config.setup({ dc = "eu", client_id = "id", client_secret = "secret", refresh_token = "rt" })
    auth.invalidate()
    original_raw = client.raw
    calls = {}
  end)

  after_each(function()
    client.raw = original_raw
  end)

  local function stub(responders)
    client.raw = function(method, url, opts, cb)
      table.insert(calls, { method = method, url = url, opts = opts })
      for pattern, fn in pairs(responders) do
        if url:find(pattern, 1, true) then
          local r, e = fn(opts)
          return vim.schedule(function()
            cb(r, e)
          end)
        end
      end
      error("unexpected url " .. url)
    end
  end

  it("refreshes once and caches the token", function()
    stub({ ["/oauth/v2/token"] = function(opts)
      assert.are.equal("refresh_token", opts.form.grant_type)
      return { status = 200, body = { access_token = "AT1", expires_in = 3600 } }
    end })
    assert.are.equal("AT1", await(auth.token))
    assert.are.equal("AT1", await(auth.token))
    assert.are.equal(1, #calls)
    assert.are.equal("https://accounts.zoho.eu/oauth/v2/token", calls[1].url)
  end)

  it("shares one refresh between concurrent callers", function()
    stub({ ["/oauth/v2/token"] = function()
      return { status = 200, body = { access_token = "AT", expires_in = 3600 } }
    end })
    local got = {}
    auth.token(function(t) table.insert(got, t) end)
    auth.token(function(t) table.insert(got, t) end)
    vim.wait(1000, function() return #got == 2 end, 5)
    assert.are.same({ "AT", "AT" }, got)
    assert.are.equal(1, #calls)
  end)

  it("explains a revoked refresh token", function()
    stub({ ["/oauth/v2/token"] = function()
      return nil, { message = "invalid_code", type = "http" }
    end })
    local token, err = await(auth.token)
    assert.is_nil(token)
    assert.truthy(err.message:find("data centre", 1, true))
  end)

  it("sends the Zoho auth header and retries once after a 401", function()
    local tokens = { "OLD", "NEW" }
    local api_calls = 0
    stub({
      ["/oauth/v2/token"] = function()
        return { status = 200, body = { access_token = table.remove(tokens, 1), expires_in = 3600 } }
      end,
      ["/zsapi/teams/"] = function(opts)
        api_calls = api_calls + 1
        if opts.headers.Authorization == "Zoho-oauthtoken OLD" then
          return nil, { status = 401, message = "INVALID_OAUTHTOKEN" }
        end
        return { status = 200, body = { portals = {} } }
      end,
    })
    local result, err = await(function(cb) client.request("GET", "/teams/", {}, cb) end)
    assert.is_nil(err)
    assert.are.same({}, result.body.portals)
    assert.are.equal(2, api_calls)
  end)

  it("fails fast without credentials", function()
    config.setup({ client_id = "", client_secret = "", refresh_token = "" })
    stub({})
    local token, err = await(auth.token)
    assert.is_nil(token)
    assert.are.equal("auth", err.type)
    assert.are.equal(0, #calls)
  end)
end)
