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
`m m` also create a selection over the range they travel. In SEL mode, cursor
motions extend the current selection. Viewport alignment (`z c`, `z z`,
`z t`, `z b`) leaves the cursor line and the selection in place.

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
| `n` `N` | next / previous search match |
| `*` `#` | search current word down / up |
| `r` | refresh from pane |
| `:` | goto line (prompt) |

## Configuration

Options (set before `run-shell` / TPM):

- `@copy-mode-helix-clipboard` – override the clipboard command used for `y`/`Enter`
  (default: auto-detect `wl-copy`, `xclip`, `xsel`, or `pbcopy`)
- `@copy-mode-helix-position-indicator` – `on` (default) or `off`; controls whether
  `SEL`/`NOR` is shown in the top-right copy-mode position indicator.

## Notes / limitations

tmux copy-mode cannot edit text, run LSP, or parse syntax trees, so the
full set of Helix editing, text-object, window, and space-mode commands is
not emulated. Motion and selection features above are the supported subset.

- `g w` (goto word) is not implemented; it reports that tree-sitter is required.
- Only the `[p` / `]p` bracket subcommands are implemented.
