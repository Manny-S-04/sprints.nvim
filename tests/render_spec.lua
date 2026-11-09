local render = require("sprints.ui.render")

describe("sprints.ui.render", function()
  it("renders an item with metadata, html description and comments", function()
    local lines = render.render({
      key = "I7", summary = "Fix login", status = "In Progress", assignee = "Manny",
      updated = "1700000000000", description = "<div>Steps<br>1</div>",
      comments = { { author = "Sam", created = "2026-10-27T10:00:00", body = "<p>ok</p>" } },
    })
    assert.are.equal("# I7", lines[1])
    assert.are.equal("Fix login", lines[3])
    assert.truthy(vim.tbl_contains(lines, "Status:       In Progress"))
    assert.truthy(vim.tbl_contains(lines, "Updated:      " .. os.date("%Y-%m-%d %H:%M", 1700000000)))
    assert.truthy(vim.tbl_contains(lines, "Owners:       Manny"))
    assert.truthy(vim.tbl_contains(lines, "Steps"))
    assert.truthy(vim.tbl_contains(lines, "Sam — 2026-10-27 10:00"))
    assert.are.equal("ok", lines[#lines])
  end)

  it("says why comments are missing", function()
    local lines = render.render({ key = "I1", comments_error = "HTTP 404" })
    assert.are.equal("(comments unavailable: HTTP 404)", lines[#lines])
  end)

  it("shows (none) for no owners", function()
    assert.truthy(vim.tbl_contains(render.render({ key = "I1" }), "Owners:       (none)"))
  end)

  it("aligns list rows with type, points and owner initials", function()
    local a = { key = "I1", status = "Done", issue_type = "Bug", points = 3, assignee = "Manny Singh, Sam Clarke", summary = "a", status_category = "done" }
    local b = { key = "I10", status = "To do", issue_type = "Story", summary = "b" }
    local lines, hls, by_line = render.render_list("Sprint 4", { a, b })
    assert.are.equal("I1   Done   Bug    3  MS SC  a", lines[3])
    assert.are.equal("I10  To do  Story     -      b", lines[4])
    assert.are.equal(b, by_line[4])
    assert.are.equal("sprintsStatusDone", hls[3].hl_group)
  end)

  it("groups by status in project order for the board view", function()
    local items = {
      { key = "I1", status = "Done", status_id = "s3", summary = "a" },
      { key = "I2", status = "To do", status_id = "s1", summary = "b" },
      { key = "I3", status = "To do", status_id = "s1", summary = "c" },
    }
    local lines, _, by_line = render.render_list("Board", items, { group = true, status_order = { "s1", "s2", "s3" } })
    assert.are.same({ "# Board", "", "## To do (2)", "I2  -  b", "I3  -  c", "", "## Done (1)", "I1  -  a" },
      vim.tbl_map(function(l) return (l:gsub("%s%s+", "  "):gsub("%s+$", "")) end, lines))
    assert.are.equal("I1", by_line[8].key)
  end)

  it("initials skip raw ids", function()
    assert.are.equal("MS ?", render.initials("Manny Singh, 13969123456799009"))
    assert.are.equal("-", render.initials(nil))
  end)
end)
