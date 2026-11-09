local project = vim.fn.getcwd()
vim.o.swapfile = false
vim.opt.rtp:prepend(project)
vim.opt.rtp:prepend(assert(vim.env.GITSIGNS_RTP, 'Set GITSIGNS_RTP to a gitsigns.nvim checkout'))
vim.env.PATH = project .. '/tests:' .. vim.env.PATH
vim.cmd('runtime plugin/slop.lua')
local slop = require('slop')
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, 'p')
vim.env.SLOP_TEST_STATE = tmp .. '/github.json'
local state
local function read()
  state = vim.json.decode(table.concat(vim.fn.readfile(vim.env.SLOP_TEST_STATE), '\n'))
  return state
end
local function write()
  vim.fn.writefile({ vim.json.encode(state) }, vim.env.SLOP_TEST_STATE)
end
local function eq(expected, actual)
  assert(
    vim.deep_equal(expected, actual),
    '\nexpected: ' .. vim.inspect(expected) .. '\nactual: ' .. vim.inspect(actual)
  )
end
local function fails(f, message)
  local ok, err = pcall(f)
  assert(not ok and tostring(err):find(message, 1, true), 'Expected failure: ' .. message .. '\nGot: ' .. tostring(err))
end
local function git(...)
  local r = vim.system(vim.list_extend({ 'git', '-C', tmp }, { ... }), { text = true }):wait()
  assert(r.code == 0, r.stderr)
  return vim.trim(r.stdout)
end
local function close()
  vim.cmd('close!')
end
local function set(lines)
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end
local function save()
  vim.cmd('write')
end
local function start(mode)
  local id = vim.fn.getqflist({ id = 0 }).id
  slop.start(mode)
  assert(
    vim.wait(5000, function()
      return vim.fn.getqflist({ id = 0 }).id ~= id
    end),
    'Gitsigns did not populate quickfix'
  )
end
local function source()
  vim.cmd.edit(vim.fn.fnameescape(tmp .. '/file.lua'))
end

local function test()
  git('init', '-q')
  git('config', 'user.name', 'Test')
  git('config', 'user.email', 'test@example.com')
  vim.fn.writefile({ 'one', 'two', 'three', 'four', 'five' }, tmp .. '/file.lua')
  git('add', '.')
  git('commit', '-qm', 'base')
  local base = git('rev-parse', 'HEAD')
  vim.fn.writefile({ 'ONE', 'TWO', 'three', 'four', 'FIVE' }, tmp .. '/file.lua')
  git('commit', '-qam', 'PR')
  state = {
    pr = {
      id = 'PR',
      number = 7,
      url = 'https://github.com/test/repo/pull/7',
      baseRefOid = base,
      headRefOid = git('rev-parse', 'HEAD'),
    },
    comments = {},
  }
  write()
  vim.cmd.cd(tmp)
  require('gitsigns').setup({ attach_to_untracked = true })
  source()
  assert(
    vim.wait(5000, function()
      return vim.b.gitsigns_head ~= nil
    end),
    'Gitsigns did not attach'
  )
  start('pr')
  eq(base, require('gitsigns.config').config.base)
  eq(true, vim.fn.getqflist({ context = 0 }).context.slop)
  assert(#vim.fn.getqflist() > 0)
  eq(tmp .. '/file.lua', vim.api.nvim_buf_get_name(0))
  -- Native quickfix navigation and mark-viewed do not touch GitHub.
  vim.fn.setloclist(0, {}, ' ', { items = { { filename = tmp .. '/file.lua', lnum = 1, text = 'unrelated' } } })
  vim.cmd('lopen')
  fails(slop.viewed, 'not a location list')
  vim.cmd('lclose')
  local items = vim.fn.getqflist()
  vim.cmd('copen')
  vim.api.nvim_win_set_cursor(0, { #items, 0 })
  slop.viewed()
  table.remove(items)
  eq(items, vim.fn.getqflist())
  vim.cmd('cclose')
  source()
  local total = #vim.fn.getqflist()
  slop.viewed()
  eq(total - 1, #vim.fn.getqflist())
  vim.fn.setqflist({}, ' ', { items = {}, title = 'Other list' })
  fails(slop.viewed, 'not the active Slop review')

  -- Quitting or saving empty must not even create a pending review.
  slop.comment(1, 2)
  close()
  eq(nil, read().review)
  slop.comment(1, 2)
  save()
  eq(nil, read().review)
  close()
  slop.comment(1, 2)
  set({ 'discard me' })
  close()
  eq(nil, read().review)

  -- A range anchors the last line and carries startLine/startSide.
  slop.comment(1, 2)
  slop.suggest()
  eq({ '```suggestion', 'ONE', 'TWO', '```' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  set({ 'Use this:', '```suggestion', 'new one', 'new two', '```' })
  save()
  local body = read().comments[1].body
  eq('draft-review', state.review)
  eq(2, state.comments[1].line)
  eq(1, state.comments[1].startLine)
  set({ 'Updated draft' })
  save()
  eq(1, #read().comments)
  eq('Updated draft', state.comments[1].body)
  set({ '' })
  save()
  eq('Updated draft', read().comments[1].body)
  close()

  -- Existing review, single-line comment, :wq submits exactly once.
  slop.comment(5, 5)
  set({ 'Second comment' })
  vim.cmd('wq')
  eq(2, #read().comments)
  eq(vim.NIL, state.comments[2].startLine)
  slop.comment(3, 3)
  set({ 'Third comment (pagination)' })
  vim.cmd('wq')
  eq(3, #read().comments)

  -- Failed :wq must leave text available and modified for retry.
  slop.comment(1, 1)
  set({ 'Preserve on failure' })
  local failed_buf = vim.api.nvim_get_current_buf()
  read().fail_write = true
  write()
  fails(function()
    vim.cmd('wq')
  end, 'simulated network failure')
  eq(true, vim.api.nvim_buf_is_valid(failed_buf))
  eq(true, vim.bo[failed_buf].modified)
  read().fail_write = nil
  write()
  close()

  local list = slop.drafts()
  eq(3, vim.api.nvim_buf_line_count(list))
  -- The <CR> binding opens the actual draft; saving edits, not another comment.
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
  eq('markdown', vim.bo.filetype)
  set({ 'Edited from list' })
  save()
  eq(3, #read().comments)
  eq('Edited from list', state.comments[1].body)
  close()
  assert(vim.fn.win_gotoid(vim.fn.win_findbuf(list)[1]) == 1)
  -- Old list protects remotely edited comments until refreshed.
  vim.api.nvim_buf_set_lines(list, 0, 1, false, {})
  fails(save, 'Draft comment changed')
  vim.bo[list].modified = false
  list = slop.drafts()
  vim.api.nvim_buf_set_lines(list, 0, 1, false, {})
  eq(3, #read().comments)
  save()
  eq(2, #read().comments)
  save()
  eq(2, #read().comments)
  close()

  -- Dirty code cannot be anchored against GitHub's committed line numbers.
  source()
  set({ 'local edit' })
  fails(function()
    slop.comment(1, 1)
  end, 'Save/stash local changes')
  vim.bo.modified = false
  fails(function()
    slop.comment(1, 1)
  end, 'Buffer differs from the PR head')
  vim.cmd('edit!')
  slop.comment(1, 1)
  set({ 'unsaved comment' })
  fails(slop.submit, 'Save or discard')
  close()
  -- Empty review summary aborts, leaving the draft intact.
  slop.submit(true)
  save()
  eq('draft-review', read().review)
  close()
  slop.submit(true)
  set({ 'Review summary' })
  vim.cmd('wq')
  eq(vim.NIL, read().review)
  eq('Review summary', state.submitted.body)
  eq(2, #state.submitted.comments)
  fails(slop.submit, 'No draft review')

  -- Summary-only review, then a new draft submitted without a summary.
  slop.submit(true)
  set({ 'Summary only' })
  vim.cmd('wq')
  eq('Summary only', read().submitted.body)
  slop.comment(1, 1)
  set({ 'New review' })
  vim.cmd('wq')
  slop.submit()
  eq(vim.NIL, read().review)
  eq(1, #state.submitted.comments)

  -- Real visual-mode mappings preserve the selected source range.
  source()
  slop.setup({ mappings = true })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  local keys = 'Vj' .. (vim.g.maplocalleader or '\\') .. 'rc'
  vim.api.nvim_feedkeys(keys, 'xt', false)
  eq('markdown', vim.bo.filetype)
  eq(1, vim.b.slop_target.first)
  eq(2, vim.b.slop_target.last)
  slop.suggest()
  eq({ '```suggestion', 'ONE', 'TWO', '```' }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
  close()

  -- Restarting/ending the review invalidates old saved comment buffers.
  source()
  local stale = slop.comment(1, 1)
  set({ 'A saved draft' })
  save()
  slop.stop()
  set({ 'Cannot update after ending the session' })
  fails(save, 'Start a review')
  eq(true, vim.bo[stale].modified)
  close()
  source()
  start('pr')
  -- A remote submission makes an old editor read-only on its next write.
  local list2 = slop.drafts()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<CR>', true, false, true), 'xt', false)
  read().review, state.comments = nil, {}
  write()
  set({ 'Do not edit a published comment' })
  fails(save, 'no longer in your draft review')
  close()
  if vim.api.nvim_buf_is_valid(list2) then
    vim.api.nvim_buf_delete(list2, { force = true })
  end
  source()
  read().pr.headRefOid = 'changed-on-github'
  write()
  slop.comment(1, 1)
  set({ 'Reject new PR head' })
  fails(save, 'PR head changed')
  close()
  read().pr.headRefOid = git('rev-parse', 'HEAD')
  write()

  -- Default mode falls back only for no PR, never auth/API failures.
  state.pr_error = 'no pull requests found for branch'
  write()
  source()
  start()
  eq('HEAD', require('gitsigns.config').config.base)
  fails(function()
    slop.comment(1, 1)
  end, 'Comments require a PR')
  fails(function()
    slop.start('pr')
  end, 'no pull requests found')
  read().pr_error = 'authentication failed'
  write()
  fails(slop.start, 'authentication failed')
  start('local') -- Local reviews work without gh.
  vim.fn.writefile({ 'untracked' }, tmp .. '/new.lua')
  vim.fn.writefile({ 'working tree' }, tmp .. '/file.lua')
  git('add', 'file.lua')
  start('local')
  assert(#vim.fn.getqflist() >= 2, 'Local review must include staged and untracked files')
  slop.stop()
  assert(vim.wait(1000, function()
    return require('gitsigns.config').config.base == nil
  end))
  fails(slop.drafts, 'Start a review')

  -- Opt-in defaults preserve user mappings and built-in commands.
  local gc = vim.fn.maparg('gc', 'n')
  vim.keymap.set('n', '<LocalLeader>rc', '<Nop>')
  slop.setup({ mappings = true })
  eq('<Nop>', vim.fn.maparg('<LocalLeader>rc', 'n'))
  eq('<Plug>(SlopDrafts)', vim.fn.maparg('<LocalLeader>rd', 'n'))
  eq(gc, vim.fn.maparg('gc', 'n'))
  assert(body:find('```suggestion', 1, true))
end

local ok, err = xpcall(test, debug.traceback)
vim.fn.delete(tmp, 'rf')
if not ok then
  io.stderr:write(err .. '\n')
  vim.cmd('cquit 1')
end
print('All Slop integration tests passed')
vim.cmd('qa!')
