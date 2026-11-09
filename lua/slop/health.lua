local M = {}

function M.check()
  vim.health.start('slop.nvim')
  if vim.fn.has('nvim-0.11') == 1 then
    vim.health.ok('Neovim >= 0.11')
  else
    vim.health.error('Neovim >= 0.11 is required')
  end
  for _, command in ipairs({ 'git', 'gh' }) do
    if vim.fn.executable(command) == 1 then
      vim.health.ok(command .. ' is executable')
    else
      vim.health.error(command .. ' is missing from PATH')
    end
  end
  if pcall(require, 'gitsigns') then
    vim.health.ok('Gitsigns is available')
  else
    vim.health.error('Install and configure lewis6991/gitsigns.nvim')
  end
  vim.health.info('For GitHub reviews, authenticate with `gh auth login` (no network request made by this check)')
end

return M
