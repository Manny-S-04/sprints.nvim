local client = require("sprints.api.client")
local config = require("sprints.config")
local decode = require("sprints.api.decode")

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

describe("big integer ids", function()
  it("survive decoding as exact strings", function()
    local r = client.parse_result({
      code = 0,
      stdout = '{"itemIds":[13969123456722011],"itemJObj":{"13969123456722011":["A",13969123456722099,1.5,-12345678901234567]}}'
        .. "\n__SPRINTS_NVIM_STATUS__200",
    })
    assert.are.equal("13969123456722011", r.body.itemIds[1])
    assert.are.equal("13969123456722099", r.body.itemJObj["13969123456722011"][2])
    assert.are.equal(1.5, r.body.itemJObj["13969123456722011"][3])
    assert.are.equal("-12345678901234567", r.body.itemJObj["13969123456722011"][4])
  end)

  it("are left alone inside strings, small numbers, floats and exponents", function()
    local s = '{"d":"see 12345678901234567, \\"x\\" 98765432109876543","n":42,"f":12345678901234567.5,"e":1e20}'
    assert.are.equal(s, client.quote_big_ints(s))
  end)
end)

describe("decode.rows", function()
  it("keeps rows the order list doesn't mention", function()
    local rows = decode.rows({ itemIds = { "2", "missing" }, itemJObj = { ["1"] = { "A" }, ["2"] = { "B" } } }, "item")
    assert.are.same({ "2", "1" }, { rows[1].id, rows[2].id })
  end)

  it("never lets a prop named id replace the JObj key", function()
    local rows = decode.rows({ itemJObj = { k = { "A", "other" } }, item_prop = { name = 0, id = 1 } }, "item")
    assert.are.equal("k", rows[1].id)
  end)
end)

describe("sprints", function()
  local sprints = require("sprints.api.sprints")

  it("doesn't read 'inactive' as active", function()
    assert.are.equal("inactive", sprints.state_of({ sprintStatus = "Inactive" }))
    assert.are.equal("active", sprints.state_of({ sprintStatus = "In Progress" }))
    assert.are.equal("active", sprints.state_of({ sprintType = 2 }))
  end)

  it("takes backlogId from the decoded row, not the prop map's column index", function()
    local body = {
      projectJObj = { P = { "Proj", "B123" } },
      project_prop = { projName = 0, backlogId = 1 },
    }
    assert.are.equal("B123", sprints.backlog_from_details(body, "P"))
    assert.are.equal("B9", sprints.backlog_from_details({ project_prop = { backlogId = 3 }, details = { backlogId = "B9" } }, "P"))
  end)
end)

describe("sprints.sort", function()
  it("puts the active sprint first, then upcoming, then newest completed", function()
    local list = require("sprints.api.sprints").sort({
      { name = "S10", state = "completed", no = 10 }, { name = "S13", state = "upcoming", no = 13 },
      { name = "S12", state = "active", no = 12 }, { name = "S11", state = "completed", no = 11 },
    })
    assert.are.same({ "S12", "S13", "S11", "S10" }, vim.tbl_map(function(s) return s.name end, list))
  end)
end)

describe("search", function()
  it("matches every word in title or key", function()
    local c = require("sprints.commands")
    local it_ = { key = "I2", summary = "Audit list endpoint timing out" }
    assert.is_true(c.item_contains(it_, "audit TIMING"))
    assert.is_true(c.item_contains(it_, "i2"))
    assert.is_false(c.item_contains(it_, "audit pharmacy"))
  end)
end)

describe("auth.lifetime_seconds", function()
  local auth = require("sprints.api.auth")
  it("handles seconds, legacy milliseconds and expires_in_sec", function()
    assert.are.equal(3600, auth.lifetime_seconds({ expires_in = 3600 }))
    assert.are.equal(3600, auth.lifetime_seconds({ expires_in = 3600000 }))
    assert.are.equal(1800, auth.lifetime_seconds({ expires_in = 3600000, expires_in_sec = 1800 }))
    assert.are.equal(3600, auth.lifetime_seconds({}))
  end)
end)

describe(":SprintsItem matching", function()
  local commands = require("sprints.commands")
  it("finds the reference in the word under the cursor", function()
    assert.are.equal("9", commands.ref_in_word("#9"))
    assert.are.equal("PRJ-I12", commands.ref_in_word("(PRJ-I12),"))
    assert.is_nil(commands.ref_in_word("hello"))
  end)

  it("matches bare numbers, numbers with prefix, and suffixes", function()
    local it9 = { key = "I9", no = "I9" }
    assert.is_true(commands.item_matches(it9, "9"))
    assert.is_true(commands.item_matches(it9, "#9"))
    assert.is_true(commands.item_matches(it9, "i9"))
    assert.is_false(commands.item_matches({ key = "I19", no = "I19" }, "9"))
    assert.is_true(commands.item_matches({ key = "PRJ-I12", no = "PRJ-I12" }, "I12"))
    assert.is_true(commands.item_matches({ key = "I5", no = "I5" }, "PRJ-I5"))
    assert.is_false(commands.item_matches({ key = "I5", no = "I5" }, "PRJ-I15"))
  end)
end)

describe("async.pages", function()
  local async = require("sprints.api.async")
  local original

  before_each(function()
    config.setup({ page_size = 3 })
    original = client.request
  end)
  after_each(function()
    client.request = original
  end)

  it("keeps going when the server silently caps range below page_size", function()
    local all = { "a", "b", "c", "d", "e" }
    local indexes = {}
    client.request = function(_, _, opts, cb)
      table.insert(indexes, opts.query.index)
      local body = { itemIds = {}, itemJObj = {} }
      for i = opts.query.index, math.min(opts.query.index + 1, #all) do
        table.insert(body.itemIds, all[i])
        body.itemJObj[all[i]] = { all[i] }
      end
      vim.schedule(function() cb({ status = 200, body = body }) end)
    end
    local bodies = await(function(cb) async.pages("/x", {}, "item", cb) end)
    assert.are.equal(5, #(async.merge(bodies, "item")))
    assert.are.same({ 1, 3, 5, 6 }, indexes)
  end)

  it("stops, without duplicates, when the server ignores index", function()
    local calls = 0
    client.request = function(_, _, _, cb)
      calls = calls + 1
      vim.schedule(function() cb({ status = 200, body = { itemJObj = { a = { "A" }, b = { "B" }, c = { "C" } } } }) end)
    end
    local bodies = await(function(cb) async.pages("/x", {}, "item", cb) end)
    assert.are.equal(3, #(async.merge(bodies, "item")))
    assert.are.equal(2, calls)
  end)

  it("keeps page 1 even when the prefix doesn't match", function()
    client.request = function(_, _, _, cb)
      vim.schedule(function() cb({ status = 200, body = { projUserJObj = { u = { "U" } } } }) end)
    end
    local bodies = await(function(cb) async.pages("/x", {}, "user", cb) end)
    assert.are.equal(1, #bodies)
  end)
end)

describe("workspace.meta", function()
  local workspace = require("sprints.api.workspace")
  local original

  before_each(function()
    config.setup({})
    workspace.clear_cache()
    original = client.request
  end)
  after_each(function()
    client.request = original
  end)

  it("shares one fetch between parallel callers", function()
    local calls = 0
    client.request = function(_, _, _, cb)
      calls = calls + 1
      vim.schedule(function() cb({ status = 200, body = {} }) end)
    end
    local got = 0
    workspace.meta("T", "P", function(m) if m then got = got + 1 end end)
    workspace.meta("T", "P", function(m) if m then got = got + 1 end end)
    vim.wait(1000, function() return got == 2 end, 5)
    assert.are.equal(2, got)
    assert.are.equal(4, calls)
  end)
end)
