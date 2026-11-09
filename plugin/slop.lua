if vim.g.loaded_slop then
  return
end
vim.g.loaded_slop = true

vim.api.nvim_create_user_command('Slop', function(opts)
  local ok, err = pcall(require('slop').command, opts)
  if not ok then
    vim.notify('Slop: ' .. tostring(err), vim.log.levels.ERROR)
  end
end, {
  nargs = '?',
  range = true,
  desc = 'Review code with Gitsigns and GitHub draft comments',
  complete = function()
    return { 'comment', 'suggest', 'drafts', 'submit', 'submit-comment', 'viewed', 'stop' }
  end,
})

require('slop').setup()
