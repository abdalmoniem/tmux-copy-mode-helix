# copy-mode-helix

A tmux plugin that brings **Helix normal-mode motions** to tmux copy mode.

Enter copy mode with `prefix + [` and edit/navigate using Helix keys,
then yank with `y` or `Enter`.

## Installation (TPM)

```tmux
set -g @plugin 'tmux-plugins/tpm'

# Install into /home/abel/projects/copy-mode-helix or use your TPM location:
set -g @plugin '/home/abel/projects/copy-mode-helix'

run '~/.tmux/plugins/tpm/tpm'
```

## Manual installation

```tmux
run-shell /home/abel/projects/copy-mode-helix/copy-mode-helix.tmux
```

## Usage

- `prefix + [` – enter helix copy mode
- `v` / `Space` – toggle select (extend) mode
- `y` / `Enter` – yank selection to clipboard
- `Y` – yank current line
- `q` / `Escape` – cancel / clear selection

Helix `g`, `m`, `z`, `[`, `]` open a one-key sub-prompt to emulate minor modes.

## Motion keymap (copy-mode)

| Key | Action |
|---|---|
| `h j k l` / arrows | move left / down / up / right |
| `w e b` | next word / word end / previous word |
| `W E B` | same on space-delimited WORDs |
| `f t F T` | find / till (forward/backward), char prompt |
| `0 Home` | start of line |
| `^` | first non-whitespace |
| `$ End` | end of line |
| `G` | end of history |
| `C-d / C-u` | half page down / up |
| `C-f / C-b` | page down / up |
| `{ }` | previous / next paragraph |
| `g g` | history top |
| `g e` | history bottom |
| `g h / g l / g s` | line start / line end / first non-whitespace |
| `g t / g c / g b` | screen top / center / bottom |
| `z z (z c)` | center view |
| `z t / z b` | align view top / bottom |
| `z j / z k` | scroll view down / up |
| `m m` | next matching bracket |
| `[ p` / `] p` | previous / next paragraph |
| `/ ?` | search down / up |
| `n N` | repeat search |
| `* #` | search current word |
| `%` | select entire buffer |
| `x X V` | select current line |
| `;` | clear selection |
| `o` | other selection end |
| `r` | refresh pane |
| `:` | goto line |

## Notes / limitations

tmux copy-mode cannot edit text, run LSP, or parse syntax trees, so the
full set of Helix editing, text-object, window, and space-mode commands is
not emulated. Motion and selection features above are the supported subset.
