# slop.nvim

Review code where you edit it. Gitsigns shows the changes, quickfix takes you
through the hunks, and ordinary Markdown buffers hold your GitHub review comments.

```vim
:Slop                    " PR merge base, or HEAD when this branch has no PR
:cnext                   " Next hunk; :cprevious goes back
:Slop comment            " Comment on the cursor line
:'<,'>Slop comment       " Comment on a selected line range
:write                   " Save the comment to your draft review
:quit                    " Return to code
:Slop drafts             " Edit/delete draft comments
:Slop submit             " Publish the draft review
```

No PR dashboard, file picker, or custom diff renderer. Keep your Gitsigns hunk
navigation, inline previews, and native quickfix commands.

## Install

Requires **Neovim 0.11+**, **Git**, and
[Gitsigns](https://github.com/lewis6991/gitsigns.nvim). GitHub reviews also require
the [GitHub CLI](https://cli.github.com/) authenticated with `gh auth login`.
The plugin uses the CLI's repository/host selection, including GitHub Enterprise.

With lazy.nvim:

```lua
{
  'EskelinenAntti/slop.nvim',
  dependencies = { 'lewis6991/gitsigns.nvim' },
  opts = { mappings = true }, -- optional <LocalLeader>r bindings
}
```

With Neovim's `vim.pack` (on versions that provide it):

```lua
vim.pack.add({
  'https://github.com/lewis6991/gitsigns.nvim',
  'https://github.com/EskelinenAntti/slop.nvim',
})
require('gitsigns').setup({ attach_to_untracked = true })
require('slop').setup({ mappings = true })
```

If Gitsigns is already configured, keep that configuration. `attach_to_untracked`
is optional and includes untracked files in local review lists.

## Review from code

Check out the PR branch first (for example, `gh pr checkout 123`). Open a source
file and run `:Slop`. It finds the PR for the current branch, computes the merge
base, changes Gitsigns' base, fills quickfix with hunks, and opens the first hunk
in your editor. If there is no PR, it reviews local changes against `HEAD`.
Authentication and network errors are reported rather than treated as “no PR”.

Use `:Slop pr` to require a PR, or `:Slop local` to review against `HEAD` without
using GitHub. Fetch the base branch if its commit is missing locally.
`:Slop stop` ends the session and resets Gitsigns to its default index base.
There is one active review per Neovim instance; the base is global, like the
original `:Review` prototype.

## Comments and suggestions

On a source line, run `:Slop comment`. For a range, select lines with `V` and run
`:Slop comment`. A Markdown split opens:

- `:w` saves to your GitHub **draft review**; the first comment creates it.
- `:wq` / `ZZ` saves and closes; `:q!` / `ZQ` discards unsaved text.
- Saving empty/whitespace-only text aborts. An existing comment is kept.
- Further saves update the same draft comment. Saving does not publish a review.
- A failed save leaves the buffer modified, with your text available for retry.

In the comment buffer, `:Slop suggest` inserts the original source selection as a
fenced `suggestion` block. Edit the block to propose replacement text. From code,
`:Slop suggest` (also with a visual range) opens a comment with the block already
inserted. Suggestions preserve whole lines, even for characterwise selections.

New comments target the right-hand side of the PR diff. `HEAD` must match the PR
head, and the source file/buffer must match that commit. GitHub validates whether
the selected lines are commentable diff/context lines. Deleted lines remain
visible through Gitsigns; left-side inline comments are not supported.

## Draft list and submission

`:Slop drafts` loads all comments in your pending review, including drafts made
on GitHub or another client. Each line shows an ID, source range, and comment
preview. `<CR>` opens the comment for editing. Delete whole lines with `dd` (or
any native linewise operation), then `:w` to delete those comments on GitHub.
Quit without saving to discard list changes. Edit comment bodies in the separate
Markdown buffer; inline list editing is intentionally limited to deletion and
reordering. Reopen `:Slop drafts` to refresh after editing a comment.

`:Slop submit` publishes the pending review without an overall comment.
`:Slop submit-comment` opens a Markdown buffer for an overall review comment;
saving publishes the review and its drafts together. It also works without inline
comments. Saving an empty summary aborts and keeps the draft. Both commands submit
a **COMMENT** review, without approving or requesting changes.

Save or discard other modified Slop buffers before submitting or starting another
review. Changes to the PR head or to a remotely edited/submitted draft are checked
before writes. GitHub requests use synchronous native writes (up to a 30-second
timeout), so `:wq` waits for success before closing.

## Keys

No user keys are mapped by default. `setup({ mappings = true })` installs the
following only where a mapping does not already exist:

| Key | Modes | Action / `<Plug>` mapping |
| --- | --- | --- |
| `<LocalLeader>rc` | Normal, visual | Comment — `<Plug>(SlopComment)` |
| `<LocalLeader>rs` | Normal, visual | Suggestion — `<Plug>(SlopSuggest)` |
| `<LocalLeader>rd` | Normal | Draft list — `<Plug>(SlopDrafts)` |
| `<LocalLeader>rr` | Normal | Submit — `<Plug>(SlopSubmit)` |
| `<LocalLeader>rR` | Normal | Submit with summary — `<Plug>(SlopSubmitComment)` |
| `<LocalLeader>rv` | Normal | Remove quickfix item — `<Plug>(SlopViewed)` |

`<LocalLeader>` defaults to `\`. Set `vim.g.maplocalleader` before setup if you
prefer another prefix. All `<Plug>` mappings are available without setup:

```lua
vim.keymap.set({ 'n', 'x' }, '<LocalLeader>c', '<Plug>(SlopComment)')
```

Native commands remain available: `:cnext`, `:cprevious`, `:cc`, `:colder`, `:copen`,
and your existing Gitsigns mappings. `:Slop viewed` removes the selected item in
the Slop quickfix window, or the current quickfix item when called from code.
It never updates GitHub's viewed status. Rerunning `:Slop` rebuilds the list.

Full reference: `:help slop`. Dependency check: `:checkhealth slop`.

## Development

```sh
git clone https://github.com/lewis6991/gitsigns.nvim ../gitsigns.nvim
make test
# Or: make test NVIM=/path/to/nvim GITSIGNS_RTP=/path/to/gitsigns.nvim
```

Tests use real Git repositories, Gitsigns, native buffers/quickfix, and a local
GitHub CLI fixture. No credentials or network access are needed. CI runs on
Neovim 0.11.5, stable, and nightly.

Inspired by the native buffer workflow in
[guh.nvim](https://github.com/justinmk/guh.nvim), with an editor-first review flow.
MIT licensed.
