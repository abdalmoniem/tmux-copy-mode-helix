#!/usr/bin/env bash
# copy-mode-helix.tmux -- TPM entry point
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

# --- clipboard detection ------------------------------------------------------
user_clip="$(tmux show-option -gv @copy-mode-helix-clipboard 2>/dev/null || true)"
# No silent default: when neither the option nor a known tool matches, yanking
# must fail visibly (cmh_clip_or_die in scripts/common.sh) instead of piping
# the selection into /dev/null.
if [[ -n "$user_clip" ]]; then
  CLIP="$user_clip"
elif command -v wl-copy >/dev/null 2>&1; then
  CLIP="wl-copy"
elif command -v xclip >/dev/null 2>&1; then
  CLIP="xclip -selection clipboard -i"
elif command -v xsel >/dev/null 2>&1; then
  CLIP="xsel --clipboard --input"
elif command -v pbcopy >/dev/null 2>&1; then
  CLIP="pbcopy"
elif command -v termux-clipboard-set >/dev/null 2>&1; then
  CLIP="termux-clipboard-set"
fi
tmux set-option -g @cmh_clip "$CLIP" >/dev/null 2>&1

# --- clipboard validation (load time) ----------------------------------------
# Same contract the yanks enforce: a command that cannot run is announced here
# and re-checked on every yank by cmh_clip_or_die, never a silent no-op.
source "$SCRIPTS/common.sh"
if [[ -z "$CLIP" ]]; then
  cmh_alert "" "no clipboard command configured (set @copy-mode-helix-clipboard)"
elif ! command -v "${CLIP%% *}" >/dev/null 2>&1; then
  cmh_alert "" "clipboard command not found: ${CLIP%% *}"
fi

# --- base mode ---------------------------------------------------------------
tmux set-window-option -g mode-keys vi >/dev/null 2>&1

# Show current helix mode in tmux's top-right copy-mode position indicator.
indicator="$(tmux show-option -gv @copy-mode-helix-position-indicator 2>/dev/null || printf on)"
if [[ "$indicator" != "off" ]]; then
  tmux set-option -g copy-mode-position-format \
    "#[align=right](#{e|+|:#{e|-|:#{e|+|:#{history_size},#{copy_cursor_y}},#{scroll_position}},1}:#{e|+|:#{copy_cursor_x},1}) [#{scroll_position}/#{history_size}]#{?search_timed_out, (timed out),#{?search_count, (#{?@cmh_search_index,#{@cmh_search_index} / ,}#{search_count}#{?search_count_partial,+,} results),}} #[bold]#{?#{==:#{@cmh_mode},extend},SEL,NOR}#[nobold]" >/dev/null 2>&1
else
  tmux set-option -g copy-mode-position-format \
    "#[align=right](#{e|+|:#{e|-|:#{e|+|:#{history_size},#{copy_cursor_y}},#{scroll_position}},1}:#{e|+|:#{copy_cursor_x},1}) [#{scroll_position}/#{history_size}]#{?search_timed_out, (timed out),#{?search_count, (#{?@cmh_search_index,#{@cmh_search_index} / ,}#{search_count}#{?search_count_partial,+,} results),}}" >/dev/null 2>&1
fi

# --- enter copy mode ---------------------------------------------------------
tmux bind-key [ run-shell "$SCRIPTS/enter-copy-mode.sh '#{pane_id}'"

# helper: bind a copy-mode key to the unified dispatcher
bind_copy_mode_key() {
  # $1 = tmux key spec, $2 = dispatcher token
  # Synchronous: stateful handlers must observe keys in the order they were
  # pressed. run-shell -b lets fast repeats race (e.g. x x, g c, x ; e).
  tmux bind-key -T copy-mode-vi "$1" run-shell "$SCRIPTS/keys.sh '$2' '#{pane_id}'"
}

# movement
bind_copy_mode_key h h
bind_copy_mode_key j j
bind_copy_mode_key k k
bind_copy_mode_key l l
bind_copy_mode_key Left Left
bind_copy_mode_key Down Down
bind_copy_mode_key Up Up
bind_copy_mode_key Right Right

# words
bind_copy_mode_key w w
bind_copy_mode_key e e
bind_copy_mode_key b b
bind_copy_mode_key W W
bind_copy_mode_key E E
bind_copy_mode_key B B

# line / buffer
bind_copy_mode_key 0 0
bind_copy_mode_key Home Home
bind_copy_mode_key '^' caret
bind_copy_mode_key '$' dollar
bind_copy_mode_key End End
bind_copy_mode_key G G
bind_copy_mode_key '{' leftbrace
bind_copy_mode_key '}' rightbrace

# paging
bind_copy_mode_key 'C-d' 'C-d'
bind_copy_mode_key 'C-u' 'C-u'
bind_copy_mode_key 'C-f' 'C-f'
bind_copy_mode_key 'C-b' 'C-b'
bind_copy_mode_key NPage NPage
bind_copy_mode_key PPage PPage

# minor modes / prefixes
bind_copy_mode_key g g
bind_copy_mode_key z z
bind_copy_mode_key m m
bind_copy_mode_key '[' lbracket
bind_copy_mode_key ']' rbracket

# Prefix-only second keys. They must be bound to the dispatcher or tmux
# handles them directly and the pending g/z/[/] prefix never sees them.
bind_copy_mode_key c c
bind_copy_mode_key s s
bind_copy_mode_key u u
bind_copy_mode_key d d
bind_copy_mode_key p p

# selection
bind_copy_mode_key v v
bind_copy_mode_key Space space
bind_copy_mode_key x x
bind_copy_mode_key X X
bind_copy_mode_key V V
bind_copy_mode_key '%' percent
bind_copy_mode_key o o
bind_copy_mode_key ',' comma
bind_copy_mode_key '\;' semicolon

# search & misc
bind_copy_mode_key n n
bind_copy_mode_key N N
bind_copy_mode_key r r
bind_copy_mode_key '*' asterisk
bind_copy_mode_key '#' hash
bind_copy_mode_key '/' slash
bind_copy_mode_key '?' question
bind_copy_mode_key ':' colon

# misc
bind_copy_mode_key y y
bind_copy_mode_key Enter Enter
bind_copy_mode_key Y Y
bind_copy_mode_key q q
bind_copy_mode_key Escape Escape
bind_copy_mode_key ')' rightbrace

# find-char keys are dispatched through keys.sh too
bind_copy_mode_key f f
bind_copy_mode_key t t
bind_copy_mode_key F F
bind_copy_mode_key T T
