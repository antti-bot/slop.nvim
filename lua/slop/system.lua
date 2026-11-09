local M = {}

-- Argument arrays and stdin keep shell quoting and comment bodies out of commands.
function M.run(root, args, input)
  local ok, process = pcall(vim.system, args, { cwd = root, text = true, stdin = input })
  if not ok then
    error(tostring(process), 0)
  end
  local result = process:wait(30000)
  if result.code ~= 0 then
    local message = vim.trim(result.stderr or '')
    error(message ~= '' and message or ('Command failed or timed out: ' .. args[1]), 0)
  end
  return result.stdout or ''
end

function M.git(root, args)
  return vim.trim(M.run(root, vim.list_extend({ 'git' }, args)))
end

return M
