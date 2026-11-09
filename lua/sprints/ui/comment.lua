local items = require("sprints.api.items")
local util = require("sprints.ui.util")

local M = {}

---@param ref table item ref
---@param key string|nil display key, for messages
---@param on_posted fun()|nil
function M.open(ref, key, on_posted)
  key = key or ref.item
  local name = ("sprints://%s/%s/new-comment"):format(ref.project, ref.item)
  local bufnr = util.find_buf_by_name(name)
  if not bufnr then
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(bufnr, name)
    vim.bo[bufnr].buftype = "acwrite"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].filetype = "markdown"

    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      callback = function()
        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
        if not text:match("%S") then
          return vim.notify("sprints.nvim: comment is empty, nothing posted", vim.log.levels.WARN)
        end
        vim.notify("sprints.nvim: posting comment to " .. key .. "…")
        items.add_comment(ref, text, function(ok, err)
          if not ok then
            return util.notify_error("comment failed", err)
          end
          vim.notify("sprints.nvim: comment posted to " .. key)
          if vim.api.nvim_buf_is_valid(bufnr) then
            vim.bo[bufnr].modified = false
            vim.api.nvim_buf_delete(bufnr, { force = true })
          end
          if on_posted then
            on_posted()
          end
        end)
      end,
    })
  end
  util.show(bufnr)
  vim.wo.winbar = ("Comment on %s — :w to post, :q! to cancel"):format(key)
  vim.cmd("startinsert")
  return bufnr
end

return M
