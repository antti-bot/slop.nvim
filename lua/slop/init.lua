local system = require('slop.system')
local github = require('slop.github')
local buffer = require('slop.buffer')
local source = require('slop.source')
local M = {}
local session
local generation = 0
local config = { mappings = false }

local function notify(message)
  vim.notify('Slop: ' .. message)
end

local function current(expected)
  assert(session and (not expected or session == expected), 'Start a review with :Slop first')
  return session
end

local function pr_session(expected)
  local s = current(expected)
  assert(
    system.git(s.root, { 'rev-parse', 'HEAD' }) == s.pr.headRefOid,
    'HEAD must match the PR head; check out the PR branch and restart :Slop'
  )
  return s
end

local function unsaved(s, except)
  for buf in pairs(s.editors) do
    if not vim.api.nvim_buf_is_valid(buf) then
      s.editors[buf] = nil
    elseif buf ~= except then
      assert(not vim.bo[buf].modified, 'Save or discard other Slop buffers first')
    end
  end
end

-- Every review editor belongs to its opening session, including deferred writes.
local function open_editor(s, kind, lines, write)
  local buf = buffer.open(kind, lines, function(bufnr, content)
    pr_session(s)
    write(bufnr, content)
  end)
  s.editors[buf] = true
  return buf
end

local function comment_buffer(s, target, body, id)
  local original = body or ''
  local buf = open_editor(s, 'comment', vim.split(original, '\n', { plain = true }), function(_, lines)
    local text = table.concat(lines, '\n')
    if vim.trim(text) == '' then
      notify('Empty comment aborted; any existing draft comment was kept')
      return
    end
    if id then
      github.update(s, id, original, text)
    else
      -- Recheck the source: local edits must never silently shift GitHub anchors.
      source.check(s, target)
      id = github.add(s, target, text)
    end
    original = text
    notify('Comment saved to draft review')
  end)
  vim.b[buf].slop_target = target
  return buf
end

function M.start()
  if session then
    unsaved(session)
  end
  local gs = require('gitsigns')
  local filename = vim.api.nvim_buf_get_name(0)
  local cwd = vim.bo.buftype == '' and filename ~= '' and vim.fs.dirname(filename)
    or (session and session.root)
    or vim.fn.getcwd()
  local root = system.git(cwd, { 'rev-parse', '--show-toplevel' })
  local pr, host = github.pr(root)
  local merged, base = pcall(system.git, root, { 'merge-base', 'HEAD', pr.baseRefOid })
  assert(merged, 'PR base is unavailable locally; fetch the base branch and retry :Slop\n' .. base)
  local s = { root = root, pr = pr, host = host, base = base, editors = {} }
  generation = generation + 1
  local request = generation
  session = nil
  gs.change_base(s.base, true, function(err)
    if generation ~= request then
      return
    end
    if err then
      vim.notify('Slop: ' .. err, vim.log.levels.ERROR)
      return
    end
    session = s
    gs.setqflist('all', { open = false }, function(qferr)
      if generation ~= request then
        return
      end
      if qferr then
        vim.notify('Slop: ' .. qferr, vim.log.levels.ERROR)
        return
      end
      local items = {}
      for _, item in ipairs(vim.fn.getqflist()) do
        local path = vim.api.nvim_buf_get_name(item.bufnr)
        if path:sub(1, #root + 1) == root .. '/' then
          items[#items + 1] = item
        end
      end
      vim.fn.setqflist({}, 'r', {
        items = items,
        title = 'Slop: PR #' .. s.pr.number,
        context = { slop = true, root = root },
      })
      s.qfid = vim.fn.getqflist({ id = 0 }).id
      if #items > 0 then
        vim.cmd('botright copen')
        vim.cmd('wincmd p')
        vim.cmd('cfirst')
      else
        notify('No changed hunks')
      end
    end)
  end)
end

function M.comment(first, last)
  local s = pr_session()
  first = first or vim.fn.line('.')
  last = last or first
  return comment_buffer(s, source.capture(s, first, last))
end

function M.suggest(first, last)
  local target = vim.b.slop_target
  if not target then
    M.comment(first, last)
    target = vim.b.slop_target
  end
  assert(target.lines, 'Suggestions are available for comments opened from a source selection')
  local lines = { '```suggestion' }
  vim.list_extend(lines, target.lines)
  lines[#lines + 1] = '```'
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if vim.api.nvim_buf_line_count(0) == 1 and vim.fn.getline(1) == '' then
    vim.api.nvim_buf_set_lines(0, 0, 1, false, lines)
  else
    vim.api.nvim_buf_set_lines(0, row, row, false, lines)
  end
end

function M.drafts()
  local s = pr_session()
  if s.list and vim.api.nvim_buf_is_valid(s.list) then
    assert(not vim.bo[s.list].modified, 'Save or discard draft list changes first')
    vim.api.nvim_buf_delete(s.list, { force = true })
  end
  local snapshot = github.pending(s)
  local entries, order = {}, {}
  for _, comment in ipairs(snapshot.comments) do
    local label = ('%s\t%s:%s-%s\t%s'):format(
      comment.id,
      comment.path,
      comment.first,
      comment.last,
      comment.body:gsub('%s+', ' ')
    )
    entries[comment.id] = { label = label, comment = comment }
    order[#order + 1] = label
  end
  local buf = open_editor(s, 'drafts', order, function(_, lines)
    local keep = {}
    for _, line in ipairs(lines) do
      if line ~= '' then
        local id = line:match('^(%S+)\t')
        assert(
          github.find_comment(snapshot, id) and entries[id].label == line and not keep[id],
          'Only whole-line deletion/reordering is supported; press <CR> to edit a comment'
        )
        keep[id] = true
      end
    end
    local remove = {}
    for id in pairs(entries) do
      if not keep[id] then
        remove[id] = true
      end
    end
    github.delete(s, snapshot, remove)
    notify('Draft list saved')
  end)
  s.list = buf
  vim.keymap.set('n', '<CR>', function()
    local id = vim.fn.getline('.'):match('^(%S+)\t')
    local entry = entries[id]
    assert(entry and github.find_comment(snapshot, id), 'No draft comment on this line')
    pr_session(s)
    local comment = github.comment(s, id, entry.comment.body)
    -- Suggestion text is taken from source selections, never parsed from a diff.
    comment_buffer(s, { path = comment.path }, comment.body, id)
  end, { buffer = buf, desc = 'Edit draft comment' })
  return buf
end

function M.submit(with_comment)
  local s = pr_session()
  local function submit(body, except)
    pr_session(s)
    unsaved(s, except)
    github.submit(s, body)
    notify('Review submitted')
  end
  if not with_comment then
    submit()
    return
  end
  local done = false
  local buf = open_editor(s, 'review', { '' }, function(bufnr, lines)
    local body = table.concat(lines, '\n')
    if vim.trim(body) == '' then
      notify('Empty review comment aborted; draft review was kept')
      return
    end
    assert(not done, 'This review was already submitted; close this buffer')
    submit(body, bufnr)
    done = true
  end)
  return buf
end

function M.viewed()
  local s = current()
  local qf = vim.fn.getqflist({ id = 0, idx = 0, items = 0 })
  assert(qf.id == s.qfid, 'Current quickfix list is not the active Slop review')
  if #qf.items == 0 then
    return
  end
  if vim.bo.buftype == 'quickfix' then
    assert(
      vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].loclist == 0,
      'Use the Slop quickfix window, not a location list'
    )
  end
  local idx = vim.bo.buftype == 'quickfix' and vim.fn.line('.') or qf.idx
  table.remove(qf.items, idx)
  vim.fn.setqflist({}, 'r', { id = qf.id, items = qf.items, idx = math.min(idx, #qf.items) })
end

function M.stop()
  if session then
    unsaved(session)
  end
  require('gitsigns').change_base(nil, true)
  generation = generation + 1
  session = nil
end

function M.setup(opts)
  config = vim.tbl_extend('force', config, opts or {})
  local actions = {
    Comment = { command = 'comment', key = 'c', visual = true },
    Suggest = { command = 'suggest', key = 's', visual = true },
    Drafts = { command = 'drafts', key = 'd' },
    Submit = { command = 'submit', key = 'r' },
    SubmitComment = { command = 'submit-comment', key = 'R' },
    Viewed = { command = 'viewed', key = 'v' },
  }
  for name, action in pairs(actions) do
    local plug = '<Plug>(Slop' .. name .. ')'
    vim.keymap.set('n', plug, '<Cmd>Slop ' .. action.command .. '<CR>', { desc = 'Slop: ' .. action.command })
    if action.visual then
      vim.keymap.set('x', plug, ":<C-U>'<,'>Slop " .. action.command .. '<CR>', { silent = true })
    end
    if config.mappings then
      local lhs = '<LocalLeader>r' .. action.key
      for _, mode in ipairs(action.visual and { 'n', 'x' } or { 'n' }) do
        if vim.fn.maparg(lhs, mode) == '' then
          vim.keymap.set(mode, lhs, plug, { desc = 'Slop: ' .. action.command })
        end
      end
    end
  end
end

function M.command(opts)
  local action = opts.fargs[1]
  if not action then
    M.start()
  elseif action == 'comment' or action == 'suggest' then
    M[action](opts.line1, opts.line2)
  elseif action == 'submit-comment' then
    M.submit(true)
  elseif action == 'drafts' or action == 'submit' or action == 'viewed' or action == 'stop' then
    M[action]()
  else
    error('Unknown Slop action: ' .. action, 0)
  end
end

return M
