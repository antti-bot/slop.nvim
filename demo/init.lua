vim.opt.rtp:prepend('/tmp/slop-tools/gitsigns.nvim')
vim.opt.rtp:prepend('/home/antti/code/slop.nvim')
vim.env.PATH = '/home/antti/code/slop.nvim/tests:' .. vim.env.PATH
vim.env.SLOP_TEST_STATE = '/tmp/slop-video-repo/github.json'
vim.o.swapfile = false
vim.o.number = true
vim.o.termguicolors = true
vim.o.showmode = false
vim.o.laststatus = 2
vim.o.cmdheight = 2
vim.o.signcolumn = 'yes'
vim.o.fillchars = 'eob: '
vim.cmd('colorscheme habamax')
vim.o.statusline = '  slop.nvim  |  %f %m%= %l:%c  '
require('gitsigns').setup({})
require('slop').setup({ mappings = true })
vim.cmd('runtime plugin/slop.lua')
