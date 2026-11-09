local html = require("sprints.html")

describe("sprints.html.to_lines", function()
  it("splits blocks and line breaks, ignoring source newlines", function()
    assert.are.same({ "one two", "three", "", "four" },
      html.to_lines("<div>one\ntwo<br>three</div>\n<div></div><p>four</p>"))
  end)

  it("renders lists, headings, emphasis and links", function()
    assert.are.same({ "# Title", "", "- **a**", "- see [docs](https://x.y)" },
      html.to_lines('<h1>Title</h1><ul><li><b>a</b></li><li>see <a href="https://x.y">docs</a></li></ul>'))
  end)

  it("numbers ordered lists", function()
    assert.are.same({ "1. a", "2. b", "", "- c" }, html.to_lines("<ol><li>a</li><li>b</li></ol><ul><li>c</li></ul>"))
  end)

  it("keeps <pre> content verbatim in a fence", function()
    assert.are.same({ "```", "  a < b", "c", "```" }, html.to_lines("<pre>  a &lt; b\nc</pre>"))
  end)

  it("decodes entities and handles empty input", function()
    assert.are.same({ "a & b ’" }, html.to_lines("a &amp; b&nbsp;&#8217;"))
    assert.are.same({}, html.to_lines(nil))
    assert.are.same({}, html.to_lines("  "))
  end)
end)
