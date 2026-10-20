#!/usr/bin/env bash
# copy-mode-helix.tmux -- TPM entry point
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

# --- clipboard detection ------------------------------------------------------
user_clip="$(tmux show-option -gv @copy-mode-helix-clipboard 2>/dev/null || true)"
CLIP="cat > /dev/null"
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
fi
tmux set-option -g @cmh_clip "$CLIP" >/dev/null 2>&1

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
k() {
  # $1 = tmux key spec, $2 = dispatcher token
  # Synchronous: stateful handlers must observe keys in the order they were
  # pressed. run-shell -b lets fast repeats race (e.g. x x, g c, x ; e).
  tmux bind-key -T copy-mode-vi "$1" run-shell "$SCRIPTS/keys.sh '$2' '#{pane_id}'"
}

# movement
k h h; k j j; k k k; k l l
k Left Left; k Down Down; k Up Up; k Right Right

# words
k w w; k e e; k b b
k W W; k E E; k B B

# line / buffer
k 0 0; k Home Home
k '^' caret
k '$' dollar
k End End
k G G
k '{' leftbrace; k '}' rightbrace

# paging
k 'C-d' 'C-d'; k 'C-u' 'C-u'; k 'C-f' 'C-f'; k 'C-b' 'C-b'
k NPage NPage; k PPage PPage

# minor modes / prefixes
k g g; k z z; k m m
k '[' lbracket; k ']' rbracket

# Prefix-only second keys. They must be bound to the dispatcher or tmux
# handles them directly and the pending g/z/[/] prefix never sees them.
k c c; k s s; k u u; k d d; k p p

# selection
k v v; k Space space
k x x; k X X; k V V
k '%' percent
k o o
k ',' comma
k '\;' semicolon

# search & misc
k n n; k N N
k r r
k '*' asterisk; k '#' hash
k '/' slash; k '?' question
k ':' colon

# misc
k y y; k Enter Enter; k Y Y
k q q; k Escape Escape
k ')' rightbrace

# find-char keys are dispatched through keys.sh too
k f f; k t t; k F F; k T T
