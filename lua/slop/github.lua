local system = require('slop.system')
local M = {}

local function graphql(session, query, variables)
  local args = { 'gh', 'api', 'graphql', '--input', '-' }
  if session.host then
    vim.list_extend(args, { '--hostname', session.host })
  end
  local result = vim.json.decode(system.run(
    session.root,
    args,
    vim.json.encode({
      query = query,
      variables = variables,
    })
  ))
  if result.errors then
    local errors = {}
    for _, err in ipairs(result.errors) do
      errors[#errors + 1] = err.message
    end
    error(table.concat(errors, '\n'), 0)
  end
  return assert(result.data, 'GitHub returned no data')
end

function M.pr(root)
  local pr = vim.json.decode(system.run(root, {
    'gh',
    'pr',
    'view',
    '--json',
    'id,number,url,baseRefOid,headRefOid',
  }))
  return pr, pr.url:match('^https?://([^/]+)')
end

-- Only the viewer's PENDING review is ever writable. Published comments are not
-- candidates, even if another client submitted the review while a buffer was open.
function M.pending(session)
  local data = graphql(
    session,
    [[
    query($pr: ID!) {
      viewer { login }
      node(id: $pr) { ... on PullRequest {
        headRefOid
        reviews(first: 100, states: PENDING) { nodes { id author { login } } }
      } }
    }
  ]],
    { pr = session.pr.id }
  )
  local pr = data.node
  assert(pr and pr.headRefOid == session.pr.headRefOid, 'PR head changed; restart :Slop')
  local review
  for _, candidate in ipairs(pr.reviews.nodes) do
    if candidate.author and candidate.author.login == data.viewer.login then
      review = candidate
      break
    end
  end
  if not review then
    return nil, {}
  end
  local comments, cursor = {}, nil
  repeat
    local page = graphql(
      session,
      [[
      query($review: ID!, $cursor: String) {
        node(id: $review) { ... on PullRequestReview {
          comments(first: 100, after: $cursor) {
            nodes { id body path line startLine originalLine originalStartLine }
            pageInfo { hasNextPage endCursor }
          }
        } }
      }
    ]],
      { review = review.id, cursor = cursor }
    ).node.comments
    vim.list_extend(comments, page.nodes)
    cursor = page.pageInfo.hasNextPage and page.pageInfo.endCursor or nil
  until not cursor
  return review.id, comments
end

local function thread(target, body)
  local input = { body = body, path = target.path, line = target.last, side = 'RIGHT' }
  if target.first ~= target.last then
    input.startLine, input.startSide = target.first, 'RIGHT'
  end
  return input
end

function M.add(session, target, body)
  local review = M.pending(session)
  local input = thread(target, body)
  if review then
    input.pullRequestReviewId = review
    local data = graphql(
      session,
      [[
      mutation($input: AddPullRequestReviewThreadInput!) {
        addPullRequestReviewThread(input: $input) { thread { comments(first: 1) { nodes { id } } } }
      }
    ]],
      { input = input }
    )
    return data.addPullRequestReviewThread.thread.comments.nodes[1].id
  end
  -- Creating the review and its first comment together avoids empty draft reviews.
  local data = graphql(
    session,
    [[
    mutation($input: AddPullRequestReviewInput!) {
      addPullRequestReview(input: $input) { pullRequestReview { comments(first: 1) { nodes { id } } } }
    }
  ]],
    { input = { pullRequestId = session.pr.id, commitOID = session.pr.headRefOid, threads = { input } } }
  )
  return data.addPullRequestReview.pullRequestReview.comments.nodes[1].id
end

function M.update(session, id, body)
  graphql(
    session,
    [[
    mutation($input: UpdatePullRequestReviewCommentInput!) {
      updatePullRequestReviewComment(input: $input) { pullRequestReviewComment { id } }
    }
  ]],
    { input = { pullRequestReviewCommentId = id, body = body } }
  )
end

function M.delete(session, id)
  graphql(
    session,
    [[
    mutation($input: DeletePullRequestReviewCommentInput!) {
      deletePullRequestReviewComment(input: $input) { clientMutationId }
    }
  ]],
    { input = { id = id } }
  )
end

function M.submit(session, review, body)
  if review then
    graphql(
      session,
      [[
      mutation($input: SubmitPullRequestReviewInput!) {
        submitPullRequestReview(input: $input) { pullRequestReview { id } }
      }
    ]],
      { input = { pullRequestReviewId = review, event = 'COMMENT', body = body } }
    )
  else
    assert(body and vim.trim(body) ~= '', 'No draft review; use :Slop submit-comment')
    graphql(
      session,
      [[
      mutation($input: AddPullRequestReviewInput!) {
        addPullRequestReview(input: $input) { pullRequestReview { id } }
      }
    ]],
      { input = { pullRequestId = session.pr.id, commitOID = session.pr.headRefOid, event = 'COMMENT', body = body } }
    )
  end
end

return M
