local client = require("sprints.api.client")
local config = require("sprints.config")
local items = require("sprints.api.items")
local workspace = require("sprints.api.workspace")

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

local META = {
  ["/itemstatus/"] = { statusJObj = { s1 = { "To do" }, s2 = { "In Progress" }, s3 = { "Done" } }, statusIds = { "s1", "s2", "s3" } },
  ["/itemtype/"] = { projItemTypeJObj = { t1 = { "Story" } } },
  ["/priority/"] = { projPriorityJObj = { p1 = { "High" } } },
  ["/users/"] = {
    userJObj = { u1 = { "Manny", "manny@example.com" }, u2 = { "Sam", "sam@example.com" } },
    user_prop = { userName = 0, email = 1 },
  },
}

local function item_page(rows, start)
  local body = { itemIds = {}, itemJObj = {}, item_prop = { itemName = 0, itemNo = 1, statusId = 2, ownerIds = 3, projItemTypeId = 4, projPriorityId = 5 } }
  for i, r in ipairs(rows) do
    local id = tostring(start + i - 1)
    table.insert(body.itemIds, id)
    body.itemJObj[id] = r
  end
  return body
end

describe("sprints.api.items", function()
  local original_request
  local requests

  before_each(function()
    config.setup({ dc = "eu", client_id = "i", client_secret = "s", refresh_token = "r", email = "MANNY@example.com", page_size = 2 })
    workspace.clear_cache()
    original_request = client.request
    requests = {}
  end)

  after_each(function()
    client.request = original_request
  end)

  local function stub(handler)
    client.request = function(method, path, opts, cb)
      table.insert(requests, { method = method, path = path, opts = opts })
      for suffix, body in pairs(META) do
        if path:sub(-#suffix) == suffix then
          return vim.schedule(function() cb({ status = 200, body = body }) end)
        end
      end
      local body, err = handler(method, path, opts)
      vim.schedule(function()
        cb(body and { status = 200, body = body } or nil, err)
      end)
    end
  end

  local ref = { team = "T", project = "P", sprint = "S" }

  it("pages through a sprint and resolves names from project metadata", function()
    stub(function(_, path, opts)
      assert.are.equal("/team/T/projects/P/sprints/S/item/", path)
      if opts.query.index == 1 then
        return item_page({ { "A", "I1", "s1", { "u1" }, "t1", "p1" }, { "B", "I2", "s2", { "u1", "u2" }, "t1", "p1" } }, 1)
      end
      return item_page({ { "C", 3, "s3", {}, "t1", "p1" } }, 3)
    end)
    local list, err = await(function(cb) items.list(ref, cb) end)
    assert.is_nil(err)
    assert.are.equal(3, #list)
    assert.are.same({ "I1", "I2", "I3" }, { list[1].key, list[2].key, list[3].key })
    assert.are.equal("In Progress", list[2].status)
    assert.are.equal("indeterminate", list[2].status_category)
    assert.are.equal("done", list[3].status_category)
    assert.are.equal("Manny, Sam", list[2].assignee)
    assert.are.equal("Story", list[1].issue_type)
    assert.are.equal("High", list[1].priority)
    assert.are.same({ team = "T", project = "P", sprint = "S", item = "2" }, list[2].ref)
  end)

  it("finds me by email and filters to my items", function()
    stub(function()
      return item_page({ { "A", "I1", "s1", { "u2" } }, { "B", "I2", "s1", "u1" } }, 1)
    end)
    local me = await(function(cb) workspace.me("T", "P", cb) end)
    assert.are.equal("u1", me)
    local mine = await(function(cb) items.list_owned(ref, me, cb) end)
    assert.are.equal(1, #mine)
    assert.are.equal("B", mine[1].summary)
  end)

  it("gets an item with comments, and survives a failing comments call", function()
    local comments_ok = true
    stub(function(_, path)
      if path:find("/notes/$") then
        if not comments_ok then
          return nil, { message = "nope" }
        end
        return { notesJObj = { n1 = { "<div>hi</div>", "u2", "1700000000000" } }, notes_prop = { notes = 0, createdBy = 1, createdTime = 2 } }
      end
      return item_page({ { "A", "I9", "s1", { "u1" } } }, 9)
    end)
    local item = await(function(cb) items.get(vim.tbl_extend("force", ref, { item = "9" }), cb) end)
    assert.are.equal("A", item.summary)
    assert.are.equal("Sam", item.comments[1].author)
    assert.are.equal("<div>hi</div>", item.comments[1].body)

    comments_ok = false
    item = await(function(cb) items.get(vim.tbl_extend("force", ref, { item = "9" }), cb) end)
    assert.are.equal("nope", item.comments_error)
  end)

  it("posts status, owners and comments as form fields", function()
    stub(function()
      return {}
    end)
    local iref = vim.tbl_extend("force", ref, { item = "9" })
    await(function(cb) items.set_status(iref, "s3", cb) end)
    await(function(cb) items.toggle_me(iref, { "u2" }, true, cb) end)
    await(function(cb) items.toggle_me(iref, { "u2", "u1" }, false, cb) end)
    await(function(cb) items.add_comment(iref, "a <b>\n\nc", cb) end)
    await(function(cb) items.update(iref, { name = "N", points = 3, priority_id = "p1" }, cb) end)
    local posts = vim.tbl_filter(function(r) return r.method == "POST" end, requests)
    assert.are.same({ statusid = "s3" }, posts[1].opts.form)
    assert.are.same({ users = { "u2", "u1" } }, posts[2].opts.form)
    assert.are.same({ users = { "u2" } }, posts[3].opts.form)
    assert.are.equal("/team/T/projects/P/sprints/S/item/9/notes/", posts[4].path)
    assert.are.equal("<div>a &lt;b&gt;</div><div>c</div>", posts[4].opts.form.name)
    assert.are.same({ name = "N", point = "3", projpriorityid = "p1" }, posts[5].opts.form)
  end)

  it("sends nothing for an empty update and rejects unknown fields", function()
    stub(function() error("no request expected") end)
    local iref = vim.tbl_extend("force", ref, { item = "9" })
    assert.is_true(await(function(cb) items.update(iref, {}, cb) end))
    local ok, err = await(function(cb) items.update(iref, { nmae = "typo" }, cb) end)
    assert.is_nil(ok)
    assert.truthy(err.message:find("unknown item field nmae", 1, true))
  end)

  it("creates in the given sprint and returns the new ref", function()
    stub(function(method, path, opts)
      assert.are.equal("POST", method)
      assert.are.equal("/team/T/projects/P/sprints/B/item/", path)
      assert.are.same({ name = "New", users = { "u1" } }, opts.form)
      return { addedItemId = "77" }
    end)
    local new_ref = await(function(cb) items.create({ team = "T", project = "P", sprint = "B" }, { name = "New", owner_ids = { "u1" } }, cb) end)
    assert.are.same({ team = "T", project = "P", sprint = "B", item = "77" }, new_ref)
    local none, err = await(function(cb) items.create(ref, { name = " " }, cb) end)
    assert.is_nil(none)
    assert.are.equal("an item needs a title", err.message)
  end)

  it("rejects empty comments without a request", function()
    stub(function() error("no request expected") end)
    local ok, err = await(function(cb) items.add_comment({}, "  ", cb) end)
    assert.is_nil(ok)
    assert.are.equal("comment is empty", err.message)
  end)

  it("fills the browse url template", function()
    config.options.item_url = "https://sprints.zoho.{dc}/t/{team}/{project}/{sprint}/{item}/{no}"
    assert.are.equal("https://sprints.zoho.eu/t/T/P/S/9/I9",
      items.browse_url({ team = "T", project = "P", sprint = "S", item = "9" }, "I9"))
  end)
end)
