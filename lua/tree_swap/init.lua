-- Selection-aware sibling swaps using Neovim's built-in Tree-sitter API.
local M = {}

local function notify(message)
  vim.notify(message, vim.log.levels.INFO, { title = 'tree-swap.nvim' })
end

local function text(buf, range)
  return table.concat(vim.api.nvim_buf_get_text(buf, range[1], range[2], range[3], range[4], {}), '\n')
end

local function advance(row, col, value)
  local lines = vim.split(value, '\n', { plain = true })
  if #lines == 1 then return row, col + #value end
  return row + #lines - 1, #lines[#lines]
end

local function select_range(range)
  local sr, sc, er, ec = unpack(range)
  if vim.o.selection ~= 'exclusive' then
    if ec == 0 then
      er = er - 1
      ec = #vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1]
    end
    local line = vim.api.nvim_buf_get_lines(0, er, er + 1, false)[1]
    ec = vim.fn.byteidx(line, vim.fn.charidx(line, ec - 1))
  end
  vim.cmd.normal({ args = { vim.keycode('<Esc>') }, bang = true })
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd.normal({ args = { 'v' }, bang = true })
  vim.api.nvim_win_set_cursor(0, { er + 1, ec })
end

---Swap the selected syntax node with an adjacent list-like sibling.
---@param direction integer 1 for next, -1 for previous
function M.swap(direction)
  assert(direction == 1 or direction == -1, 'direction must be 1 or -1')
  if vim.fn.mode() ~= 'v' then
    notify('Use a characterwise syntax-node selection.')
    return
  end
  if not vim.bo.modifiable then return end

  local buf = vim.api.nvim_get_current_buf()
  local anchor, cursor = vim.fn.getpos('v'), vim.fn.getpos('.')
  local segments = vim.fn.getregionpos(anchor, cursor, { type = 'v', eol = true })
  local selected = vim.fn.getregion(anchor, cursor, { type = 'v' })
  local start = segments[1][1]
  local finish = segments[#segments][1]
  local range = { start[2] - 1, start[3] - 1, finish[2] - 1,
    finish[3] - 1 + #selected[#selected] }

  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then
    notify('No Tree-sitter parser for this buffer.')
    return
  end
  parser:parse()
  local tree = parser:language_for_range(range)
  local node = tree:named_node_for_range(range)
  if not node or not vim.deep_equal({ node:range() }, range) then
    notify('Select a whole syntax node before swapping.')
    return
  end

  -- Some grammars wrap expressions in nodes with identical ranges.
  while node:parent() and vim.deep_equal({ node:parent():range() }, range) do
    node = node:parent()
  end
  local sibling
  if direction > 0 then
    sibling = node:next_named_sibling()
  else
    sibling = node:prev_named_sibling()
  end
  if not sibling then return end
  if node:extra() or sibling:extra() or node:has_error() or sibling:has_error()
      or node:type():find('comment') or sibling:type():find('comment') then
    notify('Cannot swap comments or nodes with syntax errors.')
    return
  end
  local other = { sibling:range() }
  local left, right = range, other
  if direction < 0 then left, right = other, range end
  local gap = text(buf, { left[3], left[4], right[1], right[2] })
  -- Don't swap arbitrary AST children or reassociate intervening comments.
  if not gap:match('^%s*[,;]%s*$') then
    notify('Selection is not beside a comma/semicolon-separated sibling.')
    return
  end

  local left_text, right_text = text(buf, left), text(buf, right)
  local replacement = right_text .. gap .. left_text
  local sr, sc = left[1], left[2]
  if direction > 0 then sr, sc = advance(sr, sc, right_text .. gap) end
  local er, ec = advance(sr, sc, text(buf, range))
  -- One edit per swap preserves separators and makes undo atomic.
  vim.api.nvim_buf_set_text(buf, left[1], left[2], right[3], right[4],
    vim.split(replacement, '\n', { plain = true }))
  select_range({ sr, sc, er, ec })
end

function M.swap_next()
  M.swap(1)
end

function M.swap_previous()
  M.swap(-1)
end

return M
