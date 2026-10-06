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
assert(content() == '[\n  { b: 2,\n    a: 1 },\n  "last"\n]', 'Value cursor did not infer the whole entry')

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

-- Infer an entire keyed entry from its key or value, not the roles inside it.
local options_line = [[vim.keymap.set({ 'n', 'v' }, 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })]]
local swapped_options_line = [[vim.keymap.set({ 'n', 'v' }, 'j', "v:count == 0 ? 'gj' : 'j'", { silent = true, expr = true })]]
for _, target in ipairs({ 'expr', 'true' }) do
  normal_setup('lua', options_line, target)
  local original_cursor = vim.api.nvim_win_get_cursor(0)
  press(']a')
  assert(content() == swapped_options_line, 'Failed to infer Lua table entry from ' .. target)
  assert(vim.fn.mode() == 'n')
  assert(vim.api.nvim_win_get_cursor(0)[2] == original_cursor[2] + 15)
  press(']a')
  assert(content() == swapped_options_line, 'Climbed out at the last table entry')
  press('[a')
  assert(content() == options_line)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), original_cursor))
end
for _, case in ipairs({
  { 'javascript', 'const xs = { first: 1, second: 2 };', 'first',
    'const xs = { second: 2, first: 1 };' },
  { 'json', '{"first": 1, "second": 2}', 'first', '{"second": 2, "first": 1}' },
  { 'python', '{"first": 1, "second": 2}', 'first', '{"second": 2, "first": 1}' },
}) do
  normal_setup(case[1], case[2], case[3])
  press(']a')
  assert(content() == case[4], 'Failed to infer keyed entry in ' .. case[1])
  press('[a')
  assert(content() == case[2])
end
setup('lua', options_line, 'expr')
press(']a')
assert(content() == options_line, 'Visual selection was rounded to a larger entry')
normal_setup('lua', 'call({ expr = true }, other)', 'expr')
press(']a')
assert(content() == 'call({ expr = true }, other)', 'Climbed out of a singleton keyed entry')

-- Mixed node types with the same field role are peers in both modes.
for _, case in ipairs({
  { 'javascript', 'const entries = { first: 1, second };', 'first: 1', 'first',
    'const entries = { second, first: 1 };' },
  { 'javascript', 'const entries = { first: 1, second };', 'first: 1', '1',
    'const entries = { second, first: 1 };' },
  { 'javascript', '[a + b, c + d]', 'a + b', 'a', '[c + d, a + b]' },
  { 'javascript', '[a + b, c]', 'a + b', 'a', '[c, a + b]' },
  { 'python', '{"first": 1, **second}', '"first": 1', 'first', '{**second, "first": 1}' },
  { 'python', '{"first": 1, **second}', '"first": 1', '1', '{**second, "first": 1}' },
}) do
  setup(case[1], case[2], case[3])
  press(']a')
  assert(content() == case[5], 'Mixed Visual peers failed: ' .. content())
  press('[a')
  assert(content() == case[2])
  normal_setup(case[1], case[2], case[4])
  press(']a')
  assert(content() == case[5], 'Mixed Normal peers failed: ' .. content())
  press('[a')
  assert(content() == case[2])
end

-- Opening/closing string delimiters must infer the same item as its content.
local keymap_line = "  vim.keymap.set({ 'n', 'x' }, ']a', require('tree_swap').swap_next)"
local swapped_keymap_line = "  vim.keymap.set({ 'x', 'n' }, ']a', require('tree_swap').swap_next)"
for _, offset in ipairs({ 0, 1, 2 }) do
  normal_setup('lua', keymap_line, "'n'", offset)
  local original_cursor = vim.api.nvim_win_get_cursor(0)
  press(']a')
  assert(content() == swapped_keymap_line, 'Failed to swap Lua string at offset ' .. offset)
  assert(vim.fn.mode() == 'n')
  assert(vim.api.nvim_win_get_cursor(0)[2] == original_cursor[2] + 5)
  press('[a')
  assert(content() == keymap_line)
  assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), original_cursor))
end
for _, case in ipairs({
  { 'lua', "{ 'first', 'last' }", "'first'" },
  { 'json', '["first", "last"]', '"first"' },
  { 'javascript', '["first", "last"]', '"first"' },
  { 'python', '["first", "last"]', '"first"' },
  { 'lua', "{ '', 'last' }", "''" },
}) do
  for _, offset in ipairs({ 0, #case[3] - 1 }) do
    normal_setup(case[1], case[2], case[3], offset)
    local original_cursor = vim.api.nvim_win_get_cursor(0)
    press(']a')
    assert(content() ~= case[2], 'Delimiter swap failed for ' .. case[1])
    press('[a')
    assert(content() == case[2])
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), original_cursor))
  end
end

-- Protect comment descendants structurally, including across injection roots.
local comment_line = '-- [first, second]\nlocal other = 1'
normal_setup('lua', comment_line, 'first')
press(']a')
assert(content() == comment_line, 'Normal swap entered a comment descendant')
setup('lua', comment_line, ' [first, second]')
local comment_node = vim.treesitter.get_parser(0, 'lua'):named_node_for_range({ 0, 2, 0, 18 })
assert(not comment_node:extra() and comment_node:parent():extra(), 'Expected nested non-extra comment content')
press(']a')
assert(content() == comment_line, 'Visual swap entered non-extra comment content')

vim.treesitter.query.set('lua', 'injections', [[
  (comment (comment_content) @injection.content
    (#set! injection.language "javascript"))
]])
for _, mode in ipairs({ 'n', 'v' }) do
  if mode == 'n' then normal_setup('lua', comment_line, 'first')
  else setup('lua', comment_line, 'first') end
  local parser = vim.treesitter.get_parser(0, 'lua')
  parser:parse(true)
  assert(parser:language_for_range({ 0, 4, 0, 9 }):lang() == 'javascript', 'Comment injection not active')
  press(']a')
  assert(content() == comment_line, 'Swap escaped a comment through an injection root')
end

-- Injections outside extra nodes must still be swappable.
vim.treesitter.query.set('lua', 'injections', [[
  (string (string_content) @injection.content
    (#set! injection.language "javascript"))
]])
normal_setup('lua', "local items = '[first, second]'", 'first')
press(']a')
assert(content() == "local items = '[second, first]'", 'Safe injection swap was blocked')

-- A nested injection must not hide an extra node in an intermediate host.
vim.treesitter.query.set('javascript', 'injections', [[
  ((comment) @injection.content
    (#set! injection.language "python")
    (#offset! @injection.content 0 3 0 -3))
]])
local nested_comment = "local items = '/* [first, second] */'"
for _, mode in ipairs({ 'n', 'v' }) do
  for _, direction in ipairs({ { 'first', ']a' }, { 'second', '[a' } }) do
    if mode == 'n' then normal_setup('lua', nested_comment, direction[1])
    else setup('lua', nested_comment, direction[1]) end
    local parser = vim.treesitter.get_parser(0, 'lua')
    parser:parse(true)
    local col = assert(nested_comment:find(direction[1], 1, true)) - 1
    local range = { 0, col, 0, col + #direction[1] }
    local tree = parser:language_for_range(range)
    assert(tree:lang() == 'python', 'Innermost Python injection not active')
    assert(tree:parent():lang() == 'javascript', 'Intermediate JavaScript injection not active')
    assert(tree:parent():node_for_range(range):extra(), 'Intermediate host must be an extra node')
    assert(not tree:node_for_range(range):extra(), 'Selected Python node must not itself be extra')
    assert(not parser:node_for_range(range):extra(), 'Outer Lua host must not itself be extra')
    local cursor = vim.api.nvim_win_get_cursor(0)
    local tick = vim.api.nvim_buf_get_changedtick(0)
    press(direction[2])
    assert(content() == nested_comment, 'Nested injection escaped intermediate extra protection')
    assert(vim.api.nvim_buf_get_changedtick(0) == tick, 'Blocked nested swap made an edit')
    assert(vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor), 'Blocked nested swap moved cursor')
    assert(vim.fn.mode() == mode, 'Blocked nested swap changed mode')
  end
end
vim.treesitter.query.set('javascript', 'injections', nil)
vim.treesitter.query.set('lua', 'injections', nil)

-- Native dot-repeat resolves fresh nodes, follows direction, and respects boundaries.
normal_setup('json', '["a", "b", "c", "d"]', '"a"')
press(']a')
assert(content() == '["b", "a", "c", "d"]')
press('.')
assert(content() == '["b", "c", "a", "d"]')
press('.')
assert(content() == '["b", "c", "d", "a"]')
press('.')
assert(content() == '["b", "c", "d", "a"]', 'Dot-repeat escaped a sibling boundary')
assert(vim.fn.mode() == 'n')
press('u')
assert(content() == '["b", "c", "a", "d"]', 'Repeated swap was not a separate undo step')
press('u')
assert(content() == '["b", "a", "c", "d"]')

-- Moving to another item/buffer repeats the operation, not the original coordinates.
normal_setup('lua', 'call(first, second, third)', 'first')
press('.')
assert(content() == 'call(second, first, third)')
normal_setup('json', '["a", "b", "c"]', '"c"')
press('[a')
assert(content() == '["a", "c", "b"]')
press('.')
assert(content() == '["c", "a", "b"]')
normal_setup('lua', 'call(first, second, third)', 'second')
press('.')
assert(content() == 'call(second, first, third)', 'Repeat lost the backward direction')

-- Repeat retains keyed-entry inference and UTF-8 cursor positioning.
normal_setup('lua', '{ expr = true, silent = true, nowait = true }', 'expr')
press(']a')
press('.')
assert(content() == '{ silent = true, nowait = true, expr = true }', 'Dot lost keyed-entry inference')
normal_setup('python', '["世界", "second", "third"]', '"世界"', 1)
press(']a')
press('.')
assert(content() == '["second", "third", "世界"]', 'Dot failed on a UTF-8 string')
assert(vim.api.nvim_win_get_cursor(0)[2] == assert(content():find('世界', 1, true)) - 1)

-- A failed mapping in the opposite direction must not change the saved direction.
normal_setup('json', '["a", "b", "c"]', '"a"')
press(']a')
vim.api.nvim_win_set_cursor(0, { 1, 1 })
press('[a')
assert(content() == '["b", "a", "c"]')
press('.')
assert(content() == '["a", "b", "c"]', 'Failed swap overwrote repeat direction')

-- A regular edit replaces the swap in dot history; failed swaps preserve it.
normal_setup('json', '["one", "two", "three"]', '"one"', 1)
press(']a')
press('rZ')
assert(content() == '["two", "Zne", "three"]')
vim.api.nvim_win_set_cursor(0, { 1, assert(content():find('three', 1, true)) - 1 })
press('.')
assert(content() == '["two", "Zne", "Zhree"]', 'Swap stole dot-repeat from a regular edit')
normal_setup('lua', 'call(a, b)', 'b')
press('rB')
local previous_operator = vim.go.operatorfunc
press(']a')
assert(vim.go.operatorfunc == previous_operator, 'Failed swap replaced operatorfunc')
vim.api.nvim_win_set_cursor(0, { 1, 5 })
press('.')
assert(content() == 'call(B, B)', 'Failed swap replaced a repeatable regular edit')

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

print('PASS: Visual/Normal swaps, dot-repeat, punctuation-independent siblings, cursor/selection tracking, safety checks, undo, incremental selection, custom mappings')
