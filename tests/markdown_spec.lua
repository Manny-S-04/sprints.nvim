local markdown = require("sprints.markdown")
local html = require("sprints.html")

describe("sprints.markdown.to_html", function()
  it("converts blocks and inline markup, escaping text", function()
    assert.are.equal(
      '<h2>T</h2><div>a <b>b</b> <i>c</i> <code>x*y*z</code> <a href="https://e.x?a=1&amp;b=2">l</a><br>&lt;tag&gt;</div>'
        .. "<ul><li>one</li><li>two</li></ul><ol><li>first</li></ol><pre>if a &lt; b {}</pre>",
      markdown.to_html("## T\n\na **b** _c_ `x*y*z` [l](https://e.x?a=1&b=2)\n<tag>\n\n- one\n* two\n1. first\n```\nif a < b {}\n```")
    )
  end)

  it("leaves snake_case and lone asterisks alone", function()
    assert.are.equal("<div>snake_case_name 2 * 3 * 4</div>", markdown.to_html("snake_case_name 2 * 3 * 4"))
  end)

  it("round-trips through html.to_lines", function()
    local src = "# Plan\n\nFixed **this** and [that](https://x.y).\nSecond line\n\n1. a\n2. b\n\n- c\n\n```\ncode <x>\n```"
    assert.are.equal(src, table.concat(html.to_lines(markdown.to_html(src)), "\n"))
  end)

  it("keeps an unterminated code fence", function()
    assert.are.equal("<pre>x</pre>", markdown.to_html("```\nx"))
  end)
end)
