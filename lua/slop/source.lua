local system = require('slop.system')
local M = {}

function M.check(s, target)
  assert(target and target.path, 'No source selection for a suggestion')
  assert(
    system.git(s.root, { 'diff', '--name-only', s.pr.headRefOid, '--', target.path }) == '',
    'File differs from the PR head; save/stash local changes before commenting'
  )
  if target.buf and vim.api.nvim_buf_is_valid(target.buf) then
    assert(not vim.bo[target.buf].modified, 'Save/stash local changes before commenting')
    local head = system.run(s.root, { 'git', 'show', s.pr.headRefOid .. ':' .. target.path })
    local encoding = vim.bo[target.buf].fileencoding
    if encoding ~= '' and encoding ~= 'utf-8' then
      head = assert(vim.iconv(head, encoding, 'utf-8'), 'Unable to compare this file encoding with the PR head')
    end
    if vim.bo[target.buf].bomb then
      head = head:gsub('^\239\187\191', '')
    end
    if vim.bo[target.buf].fileformat == 'dos' then
      head = head:gsub('\r\n', '\n')
    end
    local lines = vim.split(head, '\n', { plain = true })
    if lines[#lines] == '' and #lines > 1 then
      table.remove(lines)
    end
    assert(
      vim.deep_equal(lines, vim.api.nvim_buf_get_lines(target.buf, 0, -1, false)),
      'Buffer differs from the PR head; reload the file before commenting'
    )
  end
end

function M.capture(s, first, last)
  local buf = vim.api.nvim_get_current_buf()
  assert(vim.bo[buf].buftype == '', 'Comment from a source file in the checked-out PR')
  local name = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
  local prefix = s.root .. '/'
  assert(name:sub(1, #prefix) == prefix, 'File is outside the review repository')
  local target = { path = name:sub(#prefix + 1), first = first, last = last, buf = buf }
  M.check(s, target)
  target.lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
  return target
end

return M
