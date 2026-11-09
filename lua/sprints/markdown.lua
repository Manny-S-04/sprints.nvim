local M = {}

local function escape(s)
  return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function quote_attr(s)
  return (s:gsub('"', "&quot;"))
end

local function inline(line)
  local codes = {}
  line = line:gsub("`([^`]+)`", function(c)
    table.insert(codes, c)
    return "\0" .. #codes .. "\0"
  end)
  line = line:gsub("%[([^%]]+)%]%(([^%)%s]+)%)", function(label, url)
    return ('<a href="%s">%s</a>'):format(quote_attr(url), label)
  end)
  line = line:gsub("%*%*(.-)%*%*", "<b>%1</b>")
  line = line:gsub("%f[%w%*]%*([^%*%s][^%*]-)%*%f[^%w%*]", "<i>%1</i>")
  line = line:gsub("%f[%w_]_([^_%s][^_]-)_%f[^%w_]", "<i>%1</i>")
  return (line:gsub("%z(%d+)%z", function(i)
    return "<code>" .. codes[tonumber(i)] .. "</code>"
  end))
end

---@param text string
---@return string html
function M.to_html(text)
  local lines = vim.split(text:gsub("\r\n?", "\n"), "\n", { plain = true })
  local out = {}
  local para, list, code = {}, nil, nil

  local function flush_para()
    if #para > 0 then
      table.insert(out, "<div>" .. table.concat(para, "<br>") .. "</div>")
      para = {}
    end
  end
  local function flush_list()
    if list then
      local lis = {}
      for _, it in ipairs(list.items) do
        table.insert(lis, "<li>" .. it .. "</li>")
      end
      table.insert(out, ("<%s>%s</%s>"):format(list.tag, table.concat(lis), list.tag))
      list = nil
    end
  end

  for _, raw in ipairs(lines) do
    if code then
      if raw:match("^%s*```") then
        table.insert(out, "<pre>" .. table.concat(code, "\n") .. "</pre>")
        code = nil
      else
        table.insert(code, escape(raw))
      end
    elseif raw:match("^%s*```") then
      flush_para()
      flush_list()
      code = {}
    else
      local line = escape(vim.trim(raw))
      local hashes, heading = line:match("^(#+)%s+(.*)$")
      local bullet = line:match("^[%-%*%+]%s+(.*)$")
      local numbered = line:match("^%d+[%.%)]%s+(.*)$")
      if line == "" then
        flush_para()
        flush_list()
      elseif hashes and #hashes <= 6 then
        flush_para()
        flush_list()
        table.insert(out, ("<h%d>%s</h%d>"):format(#hashes, inline(heading), #hashes))
      elseif bullet or numbered then
        flush_para()
        local tag = bullet and "ul" or "ol"
        if list and list.tag ~= tag then
          flush_list()
        end
        list = list or { tag = tag, items = {} }
        table.insert(list.items, inline(bullet or numbered))
      else
        flush_list()
        table.insert(para, inline(line))
      end
    end
  end
  if code then
    table.insert(out, "<pre>" .. table.concat(code, "\n") .. "</pre>")
  end
  flush_para()
  flush_list()
  return table.concat(out)
end

return M
