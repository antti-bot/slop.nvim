local M = {}
local serial = 0

function M.open(kind, lines, write)
  serial = serial + 1
  local buf = vim.api.nvim_create_buf(true, false)
  vim.bo[buf].buftype = 'acwrite'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.api.nvim_buf_set_name(buf, ('slop://%s/%d'):format(kind, serial))
  vim.bo[buf].filetype = kind == 'drafts' and 'slopdrafts' or 'markdown'
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.api.nvim_create_autocmd('BufWriteCmd', {
    buffer = buf,
    callback = function()
      -- Keep the buffer recoverable, including when :wq encounters an API error.
      vim.bo[buf].modified = true
      write(buf, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      vim.bo[buf].modified = false
    end,
  })
  vim.cmd('belowright 12split')
  vim.api.nvim_win_set_buf(0, buf)
  vim.wo.wrap = kind ~= 'drafts'
  vim.wo.winfixheight = true
  return buf
end

return M
