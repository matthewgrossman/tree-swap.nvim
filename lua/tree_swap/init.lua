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

local function field(node)
  local parent = node:parent()
  if not parent then return nil end
  for child, name in parent:iter_children() do
    if child:equal(node) then return name end
  end
end

local function unsafe(node)
  return node:extra() or node:has_error() or node:missing() or node:type():find('comment')
end

local function visual_range()
  local anchor, cursor = vim.fn.getpos('v'), vim.fn.getpos('.')
  local segments = vim.fn.getregionpos(anchor, cursor, { type = 'v', eol = true })
  local selected = vim.fn.getregion(anchor, cursor, { type = 'v' })
  local start = segments[1][1]
  local finish = segments[#segments][1]
  return { start[2] - 1, start[3] - 1, finish[2] - 1,
    finish[3] - 1 + #selected[#selected] }
end

local function has_peer(node)
  local role = field(node)
  for _, sibling in pairs({ node:prev_named_sibling(), node:next_named_sibling() }) do
    if not unsafe(sibling) and sibling:type() == node:type() and field(sibling) == role then
      return true
    end
  end
  return false
end

local function cursor_node(node)
  -- A non-leaf under the cursor means whitespace between tokens, not an item.
  if node:child_count() > 0 or unsafe(node) then return nil end
  -- Anonymous delimiters can belong to a named item with content (e.g. a
  -- string). Lift through that wrapper, but never infer an item from punctuation
  -- between multiple named children. This uses only tree structure.
  while not node:named() do
    local parent = node:parent()
    if not parent or parent:named_child_count() > 1 or unsafe(parent) then return nil end
    node = parent
  end
  while node:parent() do
    local parent = node:parent()
    if unsafe(parent) then return nil end
    if parent:named_child_count() > 1 then
      -- Some grammars represent wrapper markers as named nodes (e.g. literal
      -- start/content/end). A fully named, unfielded, heterogeneous wrapper has
      -- no repeated structural role, so keep climbing. No node names or token
      -- text are used to recognize these wrappers.
      local types, repeated, has_fields = {}, false, false
      for child, name in parent:iter_children() do
        if child:named() then
          repeated = repeated or types[child:type()] == true
          types[child:type()] = true
          has_fields = has_fields or name ~= nil
        end
      end
      local has_tokens = parent:child_count() > parent:named_child_count()
      -- Fixed-role children can form one repeated item (e.g. a key/value
      -- entry). Lift the complete item, never exchange its internal roles.
      -- Require syntax tokens and matching peer entries to avoid treating a
      -- call's function/arguments as interchangeable children or climbing out
      -- of a singleton argument list.
      if has_fields and has_tokens and not has_peer(node) and has_peer(parent) then
        node = parent
      elseif repeated or has_fields or has_tokens then
        -- Stop regardless of direction: a failed swap must not climb outward.
        return node
      else
        node = parent
      end
    else
      node = parent
    end
  end
end

---Swap an exact Visual selection or an inferred node at the Normal-mode cursor.
---@param direction integer 1 for next, -1 for previous
function M.swap(direction)
  assert(direction == 1 or direction == -1, 'direction must be 1 or -1')
  local mode = vim.fn.mode()
  if mode ~= 'v' and mode ~= 'n' then
    notify('Use Normal mode or a characterwise syntax-node selection.')
    return
  end
  if not vim.bo.modifiable then return end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local range = mode == 'v' and visual_range()
    or { cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2] + 1 }

  local parser = vim.treesitter.get_parser(buf, nil, { error = false })
  if not parser then
    notify('No Tree-sitter parser for this buffer.')
    return
  end
  parser:parse()
  local tree = parser:language_for_range(range)
  local node
  if mode == 'v' then
    node = tree:named_node_for_range(range)
  else
    node = tree:node_for_range(range)
  end
  if mode == 'v' then
    if not node or not vim.deep_equal({ node:range() }, range) then
      notify('Select a whole syntax node before swapping.')
      return
    end
    -- Some grammars wrap expressions in nodes with identical ranges.
    while node:parent() and vim.deep_equal({ node:parent():range() }, range) do
      node = node:parent()
    end
  else
    node = node and cursor_node(node)
    if not node then return end
    range = { node:range() }
  end
  local sibling
  if direction > 0 then
    sibling = node:next_named_sibling()
  else
    sibling = node:prev_named_sibling()
  end
  if not sibling then return end
  if unsafe(node) or unsafe(sibling) then
    notify('Cannot swap comments or nodes with syntax errors.')
    return
  end
  -- Different fields usually represent different roles (e.g. function vs.
  -- arguments). Unfielded children and repeated occurrences of one field are peers.
  if field(node) ~= field(sibling) then return end
  local other = { sibling:range() }
  local left, right = range, other
  if direction < 0 then left, right = other, range end
  local gap = text(buf, { left[3], left[4], right[1], right[2] })
  -- Reject extra/error nodes between the items, using the AST rather than text.
  for child in node:parent():iter_children() do
    local sr, sc, er, ec = child:range()
    local after_left = sr > left[3] or (sr == left[3] and sc >= left[4])
    local before_right = er < right[1] or (er == right[1] and ec <= right[2])
    if after_left and before_right and unsafe(child) then return end
  end

  local left_text, right_text = text(buf, left), text(buf, right)
  local replacement = right_text .. gap .. left_text
  local sr, sc = left[1], left[2]
  if direction > 0 then sr, sc = advance(sr, sc, right_text .. gap) end
  local er, ec = advance(sr, sc, text(buf, range))
  local cursor_prefix
  if mode == 'n' then
    cursor_prefix = text(buf, { range[1], range[2], cursor[1] - 1, cursor[2] })
  end
  -- One edit per swap preserves separators and makes undo atomic.
  vim.api.nvim_buf_set_text(buf, left[1], left[2], right[3], right[4],
    vim.split(replacement, '\n', { plain = true }))
  if mode == 'v' then
    select_range({ sr, sc, er, ec })
  else
    local row, col = advance(sr, sc, cursor_prefix)
    vim.api.nvim_win_set_cursor(0, { row + 1, col })
  end
end

function M.swap_next()
  M.swap(1)
end

function M.swap_previous()
  M.swap(-1)
end

return M
