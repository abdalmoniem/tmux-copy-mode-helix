# copy-mode-helix

A tmux plugin that brings **Helix normal-mode motions** to tmux copy mode.

Enter copy mode with `prefix + [` and edit/navigate using Helix keys,
then yank with `y` or `Enter`.

## Installation (TPM)

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'abdalmoniem/tmux-copy-mode-helix'

run '~/.tmux/plugins/tpm/tpm'
```

## Usage

- `prefix + [` – enter helix copy mode
- `v` / `Space` – toggle select (SEL) mode
- `y` / `Enter` – yank selection to clipboard and leave copy mode
- `Y` – yank current line and leave copy mode
- `q` / `Escape` – exit SEL / clear the selection; leave copy mode if neither SEL nor a selection is active

Helix `g`, `m`, `z`, `[`, `]` open a one-key sub-prompt for the commands below.

## Keymap (copy mode)

In NOR mode, plain motions move the cursor; `w e b W E B`, `f t F T`, and
`m m` also create a selection over the range they travel. Search motions
(`/`, `?`, `*`, `#`, `n`, `N`) never create or extend a selection in NOR
mode; in SEL mode they extend the current selection. In SEL mode, other cursor motions
also extend the current selection. Viewport alignment (`z c`, `z z`, `z t`,
`z b`) leaves the cursor line and the selection in place.

### Motions

| Key | Action |
|---|---|
| `h` `j` `k` `l` / arrows | left / down / up / right |
| `w` `e` `b` | next word / end of word / previous word |
| `W` `E` `B` | next WORD / end of WORD / previous WORD |
| `f` `t` `F` `T` | find / till forward, find / till backward (prompts for a character) |
| `0` `Home` | start of line |
| `^` | first non-blank character |
| `$` `End` | end of line |
| `G` | end of history |
| `{` `[p` | previous paragraph |
| `}` `]p` `)` | next paragraph |
| `C-d` `C-u` | half page down / up |
| `C-f` `C-b` / `PageDown` `PageUp` | page down / up |
| `g g` | top of history |
| `g e` | bottom of history |
| `g h` `g l` `g s` | line start / line end / first non-blank |
| `g j` `g k` | down / up one line |
| `g t` `g c` `g b` | cursor to viewport top / center / bottom |
| `m m` | next matching bracket |
| `,` | repeat last find/till in reverse |
| `z z` `z c` | center view on cursor |
| `z t` `z b` | align viewport to top / bottom |
| `z j` `z k` | scroll viewport down / up one line |
| `z u` `z d` | half page up / down |

### Selection and yank

| Key | Action |
|---|---|
| `v` / `Space` | toggle SEL mode |
| `x` / `X` / `V` | select current line; press again to extend down one line; partial selections expand to full lines |
| `%` | select entire buffer |
| `o` | switch to the other selection end |
| `;` | collapse selection to cursor (in SEL, the next motion selects from there) |
| `y` / `Enter` | yank selection and leave copy mode |
| `Y` | yank current line and leave copy mode |
| `q` / `Escape` | exit SEL / clear selection; leave copy mode if neither SEL nor a selection is active |

### Search and miscellaneous

| Key | Action |
|---|---|
| `/` `?` | search down / up (prompt) |
| `n` `N` | next match down / previous match up (always, regardless of search direction) |
| `*` `#` | search current word down / up |
| `r` | refresh from pane |
| `:` | goto line (prompt) |

`/` and `?` search with tmux regular expressions; `*` and `#` search the
word literally. A dot is a regex wildcard, so `.sh` also matches `zsh`; use
`\.sh` to match a literal `.sh`. Backslashes, quotes, and spaces typed at the
prompt are preserved.

The result counter follows the search direction: a forward search (`/`, `*`)
numbers matches from the top of the buffer, while a backward search (`?`, `#`)
numbers them from the bottom. `n` and `N` are absolute: `n` always moves to the
next match below the cursor and `N` always moves to the previous match above
it, even after a backward search. This differs from Helix/Vim, where `n`
repeats the original search direction.

## Configuration

Options (set before `run-shell` / TPM):

- `@copy-mode-helix-clipboard` – the clipboard command used for `y`/`Enter`/`Y`.
  Auto-detection (`wl-copy`, `xclip`, `xsel`, `pbcopy`) only runs while it is
  unset; there is no silent fallback command. The resolved value is validated
  at load time and on every yank: an unknown command reports
  `copy-mode-helix: clipboard command not found: bogus` and copies nothing.
  Yanks use `copy-pipe -C`, so tmux's own OSC 52 clipboard write is disabled
  and your command is the only thing that copies.
- `@copy-mode-helix-position-indicator` – `on` (default) or `off`; controls whether
  `SEL`/`NOR` is shown in the top-right copy-mode position indicator. The
  indicator has the form `[match / total results] [row:col]
  [scroll_position/history_size] [SEL|NOR]`. The match section is shown only
  while the cursor is on a search match; `n`/`N` keep it current, while any
  other cursor motion drops it until the next search or `n`/`N`. `row` is
  1-based from the bottom of the buffer (the last line is 1), like
  `scroll_position`; `col` is 1-based from the left. The match number is
  1-based from the start of the search direction: top-down for `/` and `*`,
  bottom-up for `?` and `#`.
- `@copy-mode-helix-fast-keys` – `on` (default) or `off`. Read-free motions
  (`h`/`l`, words, line/paragraph jumps, paging), the `g`/`z`/`m`/`[`/`]`
  prefixes, and search navigation (`n`/`N`, while the recorded search index is
  current) run as native tmux bindings with no shell fork, so held keys cannot
  fall behind the terminal's repeat rate. A stale search index falls back to
  the dispatcher once to recount it. Prefix chords still route through the
  dispatcher and behave the same. Set it to `off` to bind every key to the
  shell dispatcher again (the rollback path) and reload the plugin.

## Notes / limitations

tmux copy-mode cannot edit text, run LSP, or parse syntax trees, so the
full set of Helix editing, text-object, window, and space-mode commands is
not emulated. Motion and selection features above are the supported subset.

- `g w` (goto word) is not implemented; it reports that tree-sitter is required.
- Only the `[p` / `]p` bracket subcommands are implemented.
