# tree-swap.nvim

Swap Tree-sitter siblings from either a **Visual selection** or the **Normal-mode
cursor**. Select exactly what should move, or let the syntax tree infer a nearby
item. The selection or cursor follows the moved text so you can keep reordering it.

```javascript
["first", "middle", "last"]
// Select "middle" (including its quotes), then press ]a:
["first", "last", "middle"]
```

## Requirements

- Neovim 0.12+.
- An installed Tree-sitter parser for the buffer's language.
  Any parser manager, including Arborist or nvim-treesitter, can supply it.
- No dependency on nvim-treesitter-textobjects or language-specific queries.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'matthewgrossman/tree-swap.nvim',
  keys = {
    { ']a', function() require('tree_swap').swap_next() end, mode = { 'n', 'x' }, desc = 'Swap node forward' },
    { '[a', function() require('tree_swap').swap_previous() end, mode = { 'n', 'x' }, desc = 'Swap node backward' },
  },
}
```

With Neovim's built-in `vim.pack`:

```lua
vim.pack.add({ 'https://github.com/matthewgrossman/tree-swap.nvim' })
local swap = require('tree_swap')
vim.keymap.set({ 'n', 'x' }, ']a', swap.swap_next, { desc = 'Swap node forward' })
vim.keymap.set({ 'n', 'x' }, '[a', swap.swap_previous, { desc = 'Swap node backward' })
```

For local development, add the checkout to your runtimepath instead:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/tree-swap.nvim'))
local swap = require('tree_swap')
vim.keymap.set({ 'n', 'x' }, ']a', swap.swap_next)
vim.keymap.set({ 'n', 'x' }, '[a', swap.swap_previous)
```

## Selecting and swapping

The plugin creates **no mappings** and has no `setup()` or configuration options.
The examples above explicitly bind two functions in **Normal and Visual modes**:

| Key | Action |
| --- | --- |
| `]a` | Swap selected/inferred node with the next sibling |
| `[a` | Swap selected/inferred node with the previous sibling |

### Normal mode

Place the cursor inside an item and use `]a` or `[a`. The plugin starts at the
smallest token and climbs through wrappers. Anonymous delimiters in a wrapper
with at most one named child are lifted to the enclosing item, so a cursor on
either quote of a string works just like a cursor on its content. It stops at a branching parent
with repeated child types, named fields, or unnamed children, independently of
swap direction. Fully named, unfielded wrappers with distinct child types are
skipped (some grammars model literal start/content/end this way). It swaps only
an adjacent sibling with the same Tree-sitter field, including two unfielded
siblings. No punctuation values or language-specific node names are checked.

```javascript
[foo(a, b), bar()]
// Cursor on a, ]a → [foo(b, a), bar()]
// Cursor on b in the original, ]a → no change; never jumps to swapping foo(...).
```

The cursor stays at the same position within the moved text, without entering
Visual mode. Whitespace/punctuation between named children is a no-op. Different
field roles, such as a call's function and arguments, are not swapped.

Inside a keyed entry, the key and value have different field roles, but the whole
entry can itself have matching peers. In that case inference lifts to the entry
when its tree includes unnamed syntax tokens, without checking their text:

```lua
{ expr = true, silent = true }
-- Cursor on expr (or its value), ]a → { silent = true, expr = true }
```

The lift requires a safe adjacent entry with the same field role; its node type
can differ (for example, a keyed property beside a shorthand property).
Singleton entries and boundaries do not fall back to moving an enclosing list.
Visual mode never performs this lift; its selection must match the whole entry.

This is a structural heuristic, not a universal definition of a list. Grammars
can represent string fragments or other constructs as sibling groups, and
single-child containers can be indistinguishable from wrappers. Use Visual
selection when you need to control the exact scope.

### Visual mode

Use Neovim's built-in incremental selection to choose the node. For example:

```lua
vim.keymap.set({ 'n', 'x' }, '<CR>', function()
  vim.treesitter.select('parent', vim.v.count1)
end, { desc = 'Select / expand syntax node' })

vim.keymap.set('x', '<S-CR>', function()
  vim.treesitter.select('child', vim.v.count1)
end, { desc = 'Shrink syntax node selection' })
```

Press `<CR>` until the whole item is highlighted, then `]a` or `[a`. These
selection mappings are optional and are **not** installed by the plugin.
Manual characterwise selection also works when it exactly matches a named node.

### Custom mappings

```lua
local swap = require('tree_swap')
vim.keymap.set({ 'n', 'x' }, '<leader>l', swap.swap_next, { desc = 'Swap node forward' })
vim.keymap.set({ 'n', 'x' }, '<leader>h', swap.swap_previous, { desc = 'Swap node backward' })
```

## Behavior and limits

- Uses named sibling relationships and field roles, not comma/semicolon
  detection, language-specific node lists, or textobject queries. Siblings can
  be separated by punctuation, whitespace, or newlines.
- Visual mode requires an exact named-node selection. Partial strings, surrounding
  whitespace, and multi-item selections are not automatically rounded outward.
- Same-range wrapper nodes are lifted to the outermost wrapper.
- Never wraps or searches beyond the chosen sibling group when a swap fails.
- Rejects extra/error nodes and unsafe intervening siblings. Nodes inside extra
  ancestors (comments in the tested grammars) are also protected, including when
  an injected tree hides those ancestors. No comment-type-name heuristic is used;
  grammars must mark comments as extra nodes for this protection.
- Supports nested/multiline nodes, UTF-8, and inclusive/exclusive selections.
- Preserves the separator text; does not reindent or format the moved text.
- Each successful swap is one undo step and keeps the selection/cursor on the
  moved text.
- Normal mode and characterwise Visual mode only. Normal-mode swaps support native
  `.` repeat: the last successful direction is applied to a freshly inferred node
  at the current cursor, even in another buffer. Failed mappings leave the previous
  repeatable change intact; ordinary edits replace the swap in dot history.
- Visual swaps retain the selection but do not register dot-repeat. Repeat the
  mapping to keep moving the selected node. Counts are not supported yet.
- This is structural reordering, not a semantic refactoring. Reordering
  arguments or values can change program behavior. Sibling/field relationships
  do not guarantee that a swap will produce valid syntax in every grammar.

## Tests

From the repository root:

```sh
nvim --headless -u NONE -l tests/swap.lua
```

The tests require Lua, JSON, Python, JavaScript, and Bash parsers available on Neovim's
runtimepath. They exercise actual mappings and visual selections rather than
mocking Tree-sitter.
