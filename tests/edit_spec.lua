local edit = require("sprints.ui.edit")

local META = {
  statuses = { s1 = { name = "To do" }, s2 = { name = "In Progress" }, s3 = { name = "In Review" } },
  status_order = { "s1", "s2", "s3" },
  types = { t1 = { name = "Story" }, t2 = { name = "Task" } },
  type_order = { "t1", "t2" },
  priorities = { p1 = { name = "High" }, p2 = { name = "Medium" }, p3 = { name = "Low" } },
  priority_order = { "p1", "p2", "p3" },
  users = { u1 = { name = "Manny Singh" }, u2 = { name = "Sam Clarke" }, u3 = { name = "Sam Jones" } },
}
local CTX = { meta = META, me = "u1" }

local ORIGINAL = {
  key = "I1", summary = "Old title", status_id = "s1", type_id = "t1", priority_id = "p2", points = 3,
  owner_ids = { "u1" }, description = "<div>Hello <b>there</b></div>",
}

describe("edit.parse", function()
  it("splits title, fields and description", function()
    local p = edit.parse({ "", "# My title", "", "Status: To do", "owners: me, Sam", "---", "line 1", "", "line 2", "" })
    assert.are.equal("My title", p.title)
    assert.are.same({ status = "To do", owners = "me, Sam" }, p.fields)
    assert.are.equal("line 1\n\nline 2", p.description)
    assert.are.same({}, p.unknown)
  end)

  it("reports stray lines above ---", function()
    assert.are.same({ "oops" }, edit.parse({ "# t", "oops", "---" }).unknown)
  end)
end)

describe("edit.resolve", function()
  it("round-trips the template with no changes", function()
    local fields, err = edit.resolve(edit.parse(edit.template(ORIGINAL, META)), ORIGINAL, CTX)
    assert.is_nil(err)
    assert.are.same({}, fields)
  end)

  it("sends only what changed, matching names loosely", function()
    local lines = edit.template(ORIGINAL, META)
    lines[1] = "# New title"
    lines[3] = "Status: progress"
    lines[5] = "Priority: high"
    lines[7] = "Owners: me, sam c"
    local fields, err = edit.resolve(edit.parse(lines), ORIGINAL, CTX)
    assert.is_nil(err)
    assert.are.same({ name = "New title", status_id = "s2", priority_id = "p1", owner_ids = { "u1", "u2" } }, fields)
    assert.are.equal("title, status, owners, priority", edit.describe_changes(fields))
  end)

  it("explains unknown and ambiguous values and keeps nothing", function()
    local lines = edit.template(ORIGINAL, META)
    lines[4] = "Type: Epic"
    lines[7] = "Owners: sam"
    local fields, err = edit.resolve(edit.parse(lines), ORIGINAL, CTX)
    assert.is_nil(fields)
    assert.truthy(err:find('Type "Epic" is unknown; one of: Story, Task', 1, true))
    assert.truthy(err:find('Owner "sam" is ambiguous', 1, true))
  end)

  it("clears owners and points", function()
    local lines = edit.template(ORIGINAL, META)
    lines[6] = "Points:"
    lines[7] = "Owners:"
    local fields = edit.resolve(edit.parse(lines), ORIGINAL, CTX)
    assert.are.same({ points = "", owner_ids = {} }, fields)
  end)

  it("converts a changed description to HTML", function()
    local lines = edit.template(ORIGINAL, META)
    lines[#lines] = "Hello **you**"
    local fields = edit.resolve(edit.parse(lines), ORIGINAL, CTX)
    assert.are.same({ description = "<div>Hello <b>you</b></div>" }, fields)
  end)

  it("builds a new item with defaults and a target sprint", function()
    local lines = edit.template(nil, META, { sprint_name = "Sprint 12", type_id = "t1", priority_id = edit.default_priority(META) })
    assert.are.same({ "# ", "", "Type: Story", "Priority: Medium", "Points: ", "Owners: me", "Sprint: Sprint 12", "---", "" }, lines)
    lines[1] = "# Fix it"
    lines[7] = "Sprint: backlog"
    local fields, err, sprint = edit.resolve(edit.parse(lines), nil,
      { meta = META, me = "u1", sprints = { S12 = { name = "Sprint 12" }, B = { name = "Backlog" } } })
    assert.is_nil(err)
    assert.are.equal("B", sprint)
    assert.are.same({ name = "Fix it", type_id = "t1", priority_id = "p2", owner_ids = { "u1" } }, fields)
  end)

  it("requires a title", function()
    local _, err = edit.resolve(edit.parse({ "", "Type: Story", "---" }), nil, CTX)
    assert.truthy(err:find("title", 1, true))
  end)
end)
