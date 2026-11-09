local M = {}

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

local function decode_entities(s)
  s = s:gsub("&#[xX](%x+);", function(h)
    local n = tonumber(h, 16)
    return n and vim.fn.nr2char(n) or ""
  end)
  s = s:gsub("&#(%d+);", function(d)
    return vim.fn.nr2char(tonumber(d))
  end)
  return (s:gsub("&(%a+);", function(name)
    return ENTITIES[name:lower()] or ("&" .. name .. ";")
  end))
end
M.decode_entities = decode_entities

---@param html string|nil
---@return string[]
function M.to_lines(html)
  if type(html) ~= "string" or not html:match("%S") then
    return {}
  end
  local s = html:gsub("\r\n?", "\n")
  s = s:gsub("<pre[^>]*>(.-)</pre>", function(code)
    return "\n```\n" .. code:gsub("<br%s*/?>", "\n"):gsub("<[^>]->", "") .. "\n```\n"
  end)
  local parts, last = {}, 1
  for a, b in s:gmatch("()\n```\n.-\n```\n()") do
    table.insert(parts, { s:sub(last, a - 1), false })
    table.insert(parts, { s:sub(a, b - 1), true })
    last = b
  end
  table.insert(parts, { s:sub(last), false })

  local out = {}
  for _, part in ipairs(parts) do
    local text, is_code = part[1], part[2]
    if not is_code then
      text = text:gsub("\n", " ")
      text = text:gsub("<br%s*/?>", "\n")
      text = text:gsub("<h(%d)[^>]*>", function(n)
        return "\n\n" .. string.rep("#", math.min(6, tonumber(n))) .. " "
      end)
      text = text:gsub("</h%d>", "\n\n")
      text = text:gsub("<ol[^>]*>(.-)</ol>", function(inner)
        local n = 0
        return "\n" .. inner:gsub("<li[^>]*>", function()
          n = n + 1
          return "\n" .. n .. ". "
        end) .. "\n"
      end)
      text = text:gsub("<li[^>]*>", "\n- ")
      text = text:gsub("</?[ou]l[^>]*>", "\n")
      text = text:gsub("<[/]?div[^>]*>", "\n"):gsub("<[/]?p[^>]*>", "\n"):gsub("</li>", "")
      text = text:gsub("</?strong>", "**"):gsub("</?b>", "**"):gsub("</?em>", "_"):gsub("</?i>", "_")
      text = text:gsub("</?code>", "`")
      text = text:gsub('<a[^>]-href="([^"]*)"[^>]*>(.-)</a>', function(href, label)
        label = label:gsub("<[^>]->", "")
        return (label == href or label == "") and href or ("[" .. label .. "](" .. href .. ")")
      end)
      text = text:gsub("<[^>]->", "")
    end
    for line in (text .. "\n"):gmatch("(.-)\n") do
      table.insert(out, is_code and decode_entities(line) or vim.trim(decode_entities(line)))
    end
  end

  local cleaned = {}
  for _, l in ipairs(out) do
    if l ~= "" or (cleaned[#cleaned] ~= nil and cleaned[#cleaned] ~= "") then
      table.insert(cleaned, l)
    end
  end
  while cleaned[#cleaned] == "" do
    table.remove(cleaned)
  end
  return cleaned
end

return M
