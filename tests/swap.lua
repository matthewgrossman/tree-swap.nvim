-- Run from the repository root: nvim --headless -u NONE -l tests/swap.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())
local normal_next = vim.fn.maparg(']a', 'n', false, true)
local normal_previous = vim.fn.maparg('[a', 'n', false, true)
local swap = require('tree_swap')
assert(vim.fn.maparg(']a', 'x') == '')
assert(vim.fn.maparg('[a', 'x') == '')
assert(vim.deep_equal(vim.fn.maparg(']a', 'n', false, true), normal_next))
assert(vim.deep_equal(vim.fn.maparg('[a', 'n', false, true), normal_previous))
assert(swap.setup == nil, 'Plugin should not expose unused setup configuration')
vim.keymap.set({ 'n', 'x' }, ']a', swap.swap_next)
vim.keymap.set({ 'n', 'x' }, '[a', swap.swap_previous)
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
  { 'python', 'first()\nsecond()', 'first()', 'second()\nfirst()' },
  { 'bash', 'printf first second', 'first', 'printf second first' },
  { 'bash', 'first | second', 'first', 'second | first' },
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
press('V')
swap.swap_next()
assert(content() == '["first", "last"]', 'Swapped a linewise selection')
press('<Esc>')

local function normal_setup(lang, code, target, offset)
  setup(lang, code, target)
  press('<Esc>')
  local prefix = code:sub(1, assert(code:find(target, 1, true)) - 1 + (offset or 0))
  local lines = vim.split(prefix, '\n', { plain = true })
  vim.api.nvim_win_set_cursor(0, { #lines, #lines[#lines] })
end

normal_setup('json', '["first", "middle", "last"]', '"middle"', 3)
press(']a')
assert(content() == '["first", "last", "middle"]')
assert(vim.fn.mode() == 'n', 'Normal swap entered Visual mode')
assert(vim.api.nvim_win_get_cursor(0)[2] == 21, 'Cursor did not follow the string')
press('[a')
assert(content() == '["first", "middle", "last"]')
assert(vim.api.nvim_win_get_cursor(0)[2] == 13)
press('[a')
assert(content() == '["middle", "first", "last"]')

normal_setup('javascript', '[foo(a, b), bar()]', 'a')
press(']a')
assert(content() == '[foo(b, a), bar()]')
press(']a')
assert(content() == '[foo(b, a), bar()]', 'Climbed out of an inner sibling group')

for _, case in ipairs({
  { 'javascript', '[foo(a, b), bar()]', 'b', 0 },
  { 'javascript', '[foo(a), bar()]', 'a', 0 },
  { 'javascript', '[foo(a, b), bar()]', 'foo', 0 },
  { 'json', '["first", "last"]', ', ', 1 },
  { 'javascript', '["first", /* comment */ "last"]', '"first"', 2 },
}) do
  normal_setup(case[1], case[2], case[3], case[4])
  press(']a')
  assert(content() == case[2], 'Ambiguous normal-mode swap: ' .. content())
end

normal_setup('javascript', '[\n  { a: 1,\n    b: 2 },\n  "last"\n]', '1')
press(']a')
assert(content() == '[\n  { a: 1,\n    b: 2 },\n  "last"\n]')

normal_setup('python', '["世界", "last"]', '"世界"', 1)
press(']a')
assert(content() == '["last", "世界"]')
assert(vim.api.nvim_win_get_cursor(0)[2] == 10, 'UTF-8 cursor offset was lost')
press('[a')
assert(content() == '["世界", "last"]')
assert(vim.api.nvim_win_get_cursor(0)[2] == 2)
press('u')
assert(content() == '["last", "世界"]', 'Normal swap was not one undo step')

normal_setup('python', 'call("""first\nsecond""", "last")', 'second', 3)
press(']a')
assert(content() == 'call("last", """first\nsecond""")')
assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), { 2, 3 }), 'Multiline cursor offset was lost')
press('[a')
assert(content() == 'call("""first\nsecond""", "last")')

normal_setup('bash', 'printf first second', 'first', 2)
press(']a')
assert(content() == 'printf second first', 'Whitespace-separated arguments did not swap')
press(']a')
assert(content() == 'printf second first', 'Climbed out at argument boundary')
press('[a')
assert(content() == 'printf first second')

-- Missing parsers are a no-op, not an error.
vim.cmd.enew({ bang = true })
vim.bo.filetype = 'tree_swap_test_missing_parser'
vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'one, two' })
press('v')
press(']a')
assert(content() == 'one, two')
assert(notifications[#notifications] == 'No Tree-sitter parser for this buffer.')
press('<Esc>')
press(']a')
assert(content() == 'one, two')
assert(notifications[#notifications] == 'No Tree-sitter parser for this buffer.')

vim.keymap.del('x', ']a')
vim.keymap.del('x', '[a')
vim.keymap.set('x', '<leader>l', swap.swap_next)
assert(vim.fn.maparg('<leader>l', 'x', false, true).callback == swap.swap_next)
assert(vim.fn.maparg('[a', 'x') == '')
setup('json', '["first", "last"]', '"first"')
press('<leader>l')
assert(content() == '["last", "first"]', 'Custom direct binding failed')
assert(selection() == '"first"')

print('PASS: Visual/Normal swaps, punctuation-independent siblings, cursor/selection tracking, safety checks, undo, incremental selection, custom mappings')
