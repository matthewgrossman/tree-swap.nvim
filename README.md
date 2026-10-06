# tree-swap.nvim

Swap **the syntax node you selected**, not whatever happens to be under the
cursor. Expand a selection to an argument, string, or nested array item, then
move it forward or backward among its siblings. The moved item stays selected
so you can keep reordering it.

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
    { ']a', function() require('tree_swap').swap_next() end, mode = 'x', desc = 'Swap node forward' },
    { '[a', function() require('tree_swap').swap_previous() end, mode = 'x', desc = 'Swap node backward' },
  },
}
```

With Neovim's built-in `vim.pack`:

```lua
vim.pack.add({ 'https://github.com/matthewgrossman/tree-swap.nvim' })
local swap = require('tree_swap')
vim.keymap.set('x', ']a', swap.swap_next, { desc = 'Swap node forward' })
vim.keymap.set('x', '[a', swap.swap_previous, { desc = 'Swap node backward' })
```

For local development, add the checkout to your runtimepath instead:

```lua
vim.opt.runtimepath:prepend(vim.fn.expand('~/dev/tree-swap.nvim'))
local swap = require('tree_swap')
vim.keymap.set('x', ']a', swap.swap_next)
vim.keymap.set('x', '[a', swap.swap_previous)
```

## Selecting and swapping

The plugin creates **no mappings** and has no `setup()` or configuration options.
The examples above explicitly bind two functions in **Visual mode**:

| Key | Action |
| --- | --- |
| `]a` | Swap selected node with the next sibling |
| `[a` | Swap selected node with the previous sibling |

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
vim.keymap.set('x', '<leader>l', swap.swap_next, { desc = 'Swap node forward' })
vim.keymap.set('x', '<leader>h', swap.swap_previous, { desc = 'Swap node backward' })
```

## Behavior and limits

- Swaps only adjacent named siblings separated by one comma or semicolon and
  optional whitespace. Arguments, array elements, and object entries work when
  their grammar represents them this way.
- Requires an exact named-node selection. Partial strings, surrounding
  whitespace, and multi-item selections are not automatically rounded outward.
- Same-range wrapper nodes are lifted to the outermost wrapper.
- Never wraps at list boundaries or searches in another argument list.
- Rejects comments, syntax-error nodes, and gaps containing comments.
- Supports nested/multiline nodes, UTF-8, and inclusive/exclusive selections.
- Preserves the separator text; does not reindent or format the moved text.
- Each successful swap is one undo step and keeps the moved node selected.
- Characterwise Visual mode only. No count or dot-repeat support yet; repeat
  the mapping to move the selected item again.
- This is structural reordering, not a semantic refactoring. Reordering
  arguments or values can change program behavior.

## Tests

From the repository root:

```sh
nvim --headless -u NONE -l tests/swap.lua
```

The tests require Lua, JSON, Python, and JavaScript parsers available on Neovim's
runtimepath. They exercise actual mappings and visual selections rather than
mocking Tree-sitter.
