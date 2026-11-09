local decode = require("sprints.api.decode")

describe("sprints.api.decode.rows", function()
  it("names positional values with the 0-based prop map, in Ids order", function()
    local body = {
      itemIds = { "2", "1" },
      itemJObj = { ["1"] = { "First", "I1" }, ["2"] = { "Second", "I2" } },
      item_prop = { itemName = 0, itemNo = 1 },
    }
    local rows = decode.rows(body, "item")
    assert.are.same({ "2", "1" }, { rows[1].id, rows[2].id })
    assert.are.equal("Second", rows[1].itemName)
    assert.are.equal("I2", rows[1].itemNo)
    assert.are.equal("Second", rows[1].name)
  end)

  it("accepts the other prop map spellings", function()
    local rows = decode.rows({ sprintJObj = { a = { "S1", 2 } }, sprintprop = { sprintName = 0, sprintType = 1 } }, "sprint")
    assert.are.equal(2, rows[1].sprintType)
  end)

  it("falls back to sorted ids and name = first value without a prop map", function()
    local rows = decode.rows({ projectJObj = { b = { "B" }, a = { "A" } } }, "project")
    assert.are.same({ "a", "b" }, { rows[1].id, rows[2].id })
    assert.are.equal("A", rows[1].name)
  end)

  it("handles plain id -> name lookups and missing resources", function()
    assert.are.equal("Open", decode.rows({ statusJObj = { s = "Open" } }, "status")[1].name)
    assert.are.same({}, decode.rows({}, "item"))
    assert.are.same({}, decode.rows(nil, "item"))
  end)
end)

describe("sprints.api.decode helpers", function()
  it("pick skips nil, empty and vim.NIL", function()
    assert.are.equal("x", decode.pick({ a = "", b = vim.NIL, c = "x" }, { "z", "a", "b", "c" }))
    assert.is_nil(decode.pick({}, { "a" }))
  end)

  it("id_list accepts arrays, JSON strings, csv and scalars", function()
    assert.are.same({ "1", "2" }, decode.id_list({ 1, 2 }))
    assert.are.same({ "1", "2" }, decode.id_list('["1","2"]'))
    assert.are.same({ "1", "2" }, decode.id_list("1, 2"))
    assert.are.same({ "5" }, decode.id_list(5))
    assert.are.same({}, decode.id_list(vim.NIL))
  end)
end)
