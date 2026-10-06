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
  return node:extra() or node:has_error() or node:missing()
end

local function inside_extra(tree, range)
  -- Node ancestry ends at an injection root. Inspect every LanguageTree so
  -- extra nodes in intermediate hosts cannot be bypassed by nested injections.
  while tree do
    local node = tree:node_for_range(range)
    while node do
      if node:extra() then return true end
      node = node:parent()
    end
    tree = tree:parent()
  end
  return false
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
    if not unsafe(sibling) and field(sibling) == role then
      return true
    end
  end
  return false
end

local function cursor_node(node)
  -- A non-leaf under the cursor means whitespace between tokens, not an item.
  if node:child_count() > 0 or unsafe(node) then return nil end
  while node:parent() do
    local parent = node:parent()
    if unsafe(parent) then return nil end
    if parent:named_child_count() > 1 then
      -- Delimiters in wrappers can identify an item, but punctuation between
      -- multiple named children must never choose an enclosing group.
      if not node:named() then return nil end
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
      local lift_entry = has_fields and has_tokens and not has_peer(node) and has_peer(parent)
      if not lift_entry and (repeated or has_fields or has_tokens) then
        -- Stop regardless of direction: a failed swap must not climb outward.
        return node
      end
    end
    node = parent
  end
end

local function prepare_swap(direction)
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
  parser:parse(range)
  local tree = parser:language_for_range(range)
  if inside_extra(tree, range) then return end
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
  local left_node, right_node = node, sibling
  if direction < 0 then left_node, right_node = sibling, node end
  local left, right = { left_node:range() }, { right_node:range() }
  local gap = text(buf, { left[3], left[4], right[1], right[2] })
  -- Reject extra/error nodes between the items, using the AST rather than text.
  local child = left_node:next_sibling()
  while child and not child:equal(right_node) do
    if unsafe(child) then return end
    child = child:next_sibling()
  end

  local left_text, right_text = text(buf, left), text(buf, right)
  local replacement = right_text .. gap .. left_text
  local sr, sc = left[1], left[2]
  if direction > 0 then sr, sc = advance(sr, sc, right_text .. gap) end
  local tracked_text = direction > 0 and left_text or right_text
  if mode == 'n' then
    tracked_text = text(buf, { range[1], range[2], cursor[1] - 1, cursor[2] })
  end
  local row, col = advance(sr, sc, tracked_text)
  return function()
    -- One edit per swap preserves separators and makes undo atomic.
    vim.api.nvim_buf_set_text(buf, left[1], left[2], right[3], right[4],
      vim.split(replacement, '\n', { plain = true }))
    if mode == 'v' then
      select_range({ sr, sc, row, col })
    else
      vim.api.nvim_win_set_cursor(0, { row + 1, col })
    end
  end
end

local repeat_direction, pending_swap

-- Called by g@l on the initial mapping and by . on subsequent repeats.
-- Only the initial invocation uses a prepared edit; repeats resolve fresh AST
-- nodes at the current cursor, including in a different buffer.
function M._operator()
  local apply = pending_swap
  pending_swap = nil
  if not apply and repeat_direction then apply = prepare_swap(repeat_direction) end
  if apply then apply() end
end

---Swap an exact Visual selection or an inferred node at the Normal-mode cursor.
---Normal-mode swaps register the direction for native dot-repeat.
---@param direction integer 1 for next, -1 for previous
function M.swap(direction)
  assert(direction == 1 or direction == -1, 'direction must be 1 or -1')
  local apply = prepare_swap(direction)
  if not apply then return end
  if vim.fn.mode() == 'v' then
    apply()
    return
  end
  -- Don't replace the last repeatable change unless there is a valid swap.
  repeat_direction, pending_swap = direction, apply
  vim.go.operatorfunc = "v:lua.require'tree_swap'._operator"
  vim.api.nvim_feedkeys('g@l', 'ni', false)
end

function M.swap_next()
  M.swap(1)
end

function M.swap_previous()
  M.swap(-1)
end

return M
