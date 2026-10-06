-- Run from the repository root: nvim --headless -u NONE -l tests/swap.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local swap = require('tree_swap')
assert(vim.fn.maparg(']a', 'x') == '')
assert(vim.fn.maparg('[a', 'x') == '')
swap.setup()
assert(vim.fn.maparg(']a', 'x') == '', 'setup() installed a default mapping')
assert(vim.fn.maparg('[a', 'x') == '', 'setup() installed a default mapping')
vim.keymap.set('x', ']a', swap.swap_next)
vim.keymap.set('x', '[a', swap.swap_previous)
vim.keymap.set({ 'n', 'x' }, '<CR>', function()
  vim.treesitter.select('parent', vim.v.count1)
end)
vim.keymap.set('x', '<S-CR>', function()
  vim.treesitter.select('child', vim.v.count1)
end)

local notifications = {}
vim.notify = function(message) table.insert(notifications, message) end

local function press(key)
  vim.api.nvim_feedkeys(vim.keycode(key), 'xt', false)
end

local function content()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end

local function selection()
  assert(vim.fn.mode() == 'v', 'Lost visual selection')
  return table.concat(vim.fn.getregion(vim.fn.getpos('v'), vim.fn.getpos('.'), { type = 'v' }), '\n')
end

local function setup(lang, code, item)
  press('<Esc>')
  vim.cmd.enew({ bang = true })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(code, '\n', { plain = true }))
  vim.bo.filetype = lang
  local parser = vim.treesitter.get_parser(0, lang, { error = false })
  assert(parser, 'Tests require an installed ' .. lang .. ' parser')
  parser:parse()
  local offset = assert(code:find(item, 1, true)) - 1
  local prefix = code:sub(1, offset)
  local lines = vim.split(prefix, '\n', { plain = true })
  vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines] })
  press('v')
  local endlines = vim.split(prefix .. item, '\n', { plain = true })
  local col = #endlines[#endlines]
  if vim.o.selection ~= 'exclusive' then col = col - 1 end
  vim.api.nvim_win_set_cursor(0, { #endlines, col })
  assert(selection() == item)
end

local cases = {
  { 'json', '["first", "middle", "last"]', '"middle"', '["first", "last", "middle"]' },
  { 'lua', 'call(one, nested(two, three), four)', 'nested(two, three)', 'call(one, four, nested(two, three))' },
  { 'python', '["héllo", "世界", "last"]', '"世界"', '["héllo", "last", "世界"]' },
  { 'javascript', 'const xs = [\n  { a: 1,\n    b: 2 },\n  "last",\n];',
    '{ a: 1,\n    b: 2 }', 'const xs = [\n  "last",\n  { a: 1,\n    b: 2 },\n];' },
  { 'json', '{"one": 1, "two": 2}', '"one": 1', '{"two": 2, "one": 1}' },
}

for _, exclusive in ipairs({ false, true }) do
  vim.o.selection = exclusive and 'exclusive' or 'inclusive'
  for _, case in ipairs(cases) do
    setup(case[1], case[2], case[3])
    press(']a')
    assert(content() == case[4], content())
    assert(selection() == case[3], selection())
    press('[a')
    assert(content() == case[2], content())
    assert(selection() == case[3])
  end
end

vim.o.selection = 'inclusive'
for _, case in ipairs({
  { 'json', '["first", "middle", "last"]', '"last"', ']a' },
  { 'json', '["first", "middle", "last"]', '"first"', '[a' },
  { 'json', '["first", "middle", "last"]', 'idd', ']a' },
  { 'javascript', '["first", /* attached? */ "last"]', '"first"', ']a' },
  { 'lua', 'call(one, two)', 'call', ']a' },
}) do
  setup(case[1], case[2], case[3])
  press(case[4])
  assert(content() == case[2], 'Unsafe swap: ' .. content())
end

setup('lua', 'call(one, two, three)', 'two')
press(']a')
press('<CR>')
assert(selection() == '(one, three, two)', 'Cannot expand after swapping: ' .. selection())
press('<S-CR>')
assert(selection() == 'two', 'Cannot shrink after swapping')
press('<Esc>')
press('u')
assert(content() == 'call(one, two, three)', 'Swap was not one undo step')

setup('json', '["first", "middle", "last"]', '"first"')
press(']a')
press(']a')
assert(content() == '["middle", "last", "first"]', 'Repeated swap did not follow selection')
assert(selection() == '"first"')

-- A backwards visual selection chooses the same node.
setup('json', '["first", "last"]', '"first"')
press('o')
press(']a')
assert(content() == '["last", "first"]')
assert(selection() == '"first"')

setup('json', '["first", "last"]', '"first"')
vim.bo.modifiable = false
press(']a')
assert(content() == '["first", "last"]')
vim.bo.modifiable = true
press('<Esc>')
swap.swap_next()
assert(content() == '["first", "last"]', 'Swapped outside Visual mode')

-- Missing parsers are a no-op, not an error.
vim.cmd.enew({ bang = true })
vim.bo.filetype = 'tree_swap_test_missing_parser'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one, two' })
press('v')
press(']a')
assert(content() == 'one, two')
assert(notifications[#notifications] == 'No Tree-sitter parser for this buffer.')
press('<Esc>')

vim.keymap.del('x', ']a')
vim.keymap.del('x', '[a')
swap.setup({ keymaps = false })
assert(vim.fn.maparg(']a', 'x') == '')
swap.setup({ keymaps = { next = '<leader>l', previous = false } })
assert(vim.fn.maparg('<leader>l', 'x') ~= '')
assert(vim.fn.maparg('[a', 'x') == '')
vim.keymap.del('x', '<leader>l')
swap.setup({ keymaps = { next = ']a' } })
assert(vim.fn.maparg(']a', 'x', false, true).callback == swap.swap_next)
assert(vim.fn.maparg('[a', 'x') == '', 'Omitted mapping received a default')
swap.setup({ keymaps = { previous = '[a' } })
assert(vim.fn.maparg('[a', 'x', false, true).callback == swap.swap_previous)
swap.setup()
assert(vim.fn.maparg(']a', 'x', false, true).callback == swap.swap_next,
  'setup() changed an existing mapping')

print('PASS: swaps, nested/multiline/UTF-8 nodes, selection tracking, safety checks, undo, incremental selection, custom mappings')
