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
search_results_style="#{?search_timed_out, (timed out),#{?@cmh_search_index, [#{@cmh_search_index} / #{search_count}#{?search_count_partial,+,} results],}}"
cursor_index_style="[#{e|-|:#{e|+|:#{scroll_position},#{pane_height}},#{copy_cursor_y}}:#{e|+|:#{copy_cursor_x},1}] [#{scroll_position}/#{history_size}]"
indicator_style="[#[bold]#{?#{==:#{@cmh_mode},extend},SEL,NOR}#[nobold]]"
if [[ "$indicator" != "off" ]]; then
  tmux set-option -g copy-mode-position-format "#[align=right]$search_results_style $cursor_index_style $indicator_style" >/dev/null 2>&1
else
  tmux set-option -g copy-mode-position-format "#[align=right]$search_results_style $cursor_index_style" >/dev/null 2>&1
fi

# --- enter copy mode ---------------------------------------------------------
tmux bind-key [ run-shell "$SCRIPTS/enter-copy-mode.sh '#{pane_id}'"

# helper: bind a copy-mode key to the unified dispatcher
bind_copy_mode_key() {
  # $1 = tmux key spec, $2 = dispatcher token
  # Synchronous: stateful handlers must observe keys in the order they were
  # pressed. run-shell -b lets fast repeats race (e.g. x x, g c, x ; e).
  # Invoke bash directly: going through the script's '#! /usr/bin/env bash'
  # line would fork env first on every keypress.
  tmux bind-key -T copy-mode-vi "$1" run-shell "bash '$SCRIPTS/keys.sh' '$2' '#{pane_id}'"
}

# --- native fast path --------------------------------------------------------
# Held movement keys used to spend a shell fork plus three to six tmux client
# round trips per keypress, which is slower than terminal key repeat: the queue
# backed up and the cursor kept moving after release. Read-free motions can run
# entirely inside the tmux server. The binding checks whether a prefix (g/z/m/
# [/]) is pending; if one is, it hands the key to the dispatcher so chords keep
# their meaning. Otherwise it runs one command list: clear the transient state,
# branch on @cmh_mode to clear or begin a selection, send the motion, and
# repaint the indicator last. No shell and no client round trip.
fast_keys="$(tmux show-option -gv @copy-mode-helix-fast-keys 2>/dev/null || printf on)"
case "$fast_keys" in
off | 0 | no) cmh_fast_keys=0 ;;
*) cmh_fast_keys=1 ;;
esac

# Native when no prefix is queued. This exact format is already proven by the
# dispatcher's vertical fast path.
cmh_gate='#{?#{@cmh_pending},0,1}'
# Normal when @cmh_mode is unset or any value other than "extend". e|!= is a
# numeric comparator and would silently turn this into "never"; use #{!=:}.
cmh_normal='#{?#{@cmh_mode},#{!=:#{@cmh_mode},extend},1}'
cmh_clear="set-option -p @cmh_goal_col '' ; set-option -p @cmh_x_sel '' ; set-option -p @cmh_search_index '' ; set-option -p @cmh_search_pos ''"
# toggle-position is CLEAR_NEVER, so the marks survive and toggling twice
# leaves visibility unchanged. The pair must stay adjacent and last: an error
# between them would leave the indicator hidden for the rest of the session.
cmh_repaint='send-keys -X toggle-position ; send-keys -X toggle-position'

# bind_copy_mode_fast <key> <token> <select-op> <motion> <pending>
#   select-op: clear-selection for plain motions, begin-selection for word
#              motions, empty for prefixes and prefix-only second keys.
#   motion:    copy-mode motion command, empty for prefixes/second keys.
#   pending:   @cmh_pending value for a prefix key, empty otherwise.
bind_copy_mode_fast() {
  local key="$1" token="$2" select="$3" motion="$4" pending="$5"
  local body="$cmh_clear" tail fallback

  if ((!cmh_fast_keys)); then
    bind_copy_mode_key "$key" "$token"
    return
  fi
  if [[ -n "$pending" ]]; then
    body+=" ; set-option -p @cmh_pending $pending"
  fi
  if [[ -n "$motion" ]]; then
    if [[ -n "$select" ]]; then
      # The selection op and the motion stay inside the branch (and the
      # branch is the last item in the body) so select-before-motion order is
      # preserved. send-keys -X is required: copy-mode commands are not
      # top-level tmux commands.
      tail="send-keys -X $motion ; $cmh_repaint"
      body+=" ; if-shell -F '$cmh_normal' 'send-keys -X $select ; $tail' '$tail'"
    else
      body+=" ; send-keys -X $motion ; $cmh_repaint"
    fi
  else
    body+=" ; $cmh_repaint"
  fi

  # One shell command argument to run-shell: the path and pane id stay quoted
  # shell words, while #{pane_id} is expanded when run-shell executes.
  printf -v fallback "run-shell \"bash '%s/keys.sh' %s '#{pane_id}'\"" "$SCRIPTS" "$token"
  tmux bind-key -T copy-mode-vi "$key" if-shell -F "$cmh_gate" "$body" "$fallback"
}

# Search navigation is native too, but only while the recorded index still
# describes the match under the cursor. The gate checks that the index, its
# recorded position, the direction and a complete match count are all present
# and that the cursor is still on @cmh_search_pos. When any of that is stale
# (the cursor moved off the match, a search just ran but the index was cleared,
# or tmux's count is partial) the binding falls back to the dispatcher, which
# recounts from the buffer; the next n/N is native again.
#
# The native body clears the selection in normal mode (a tmux search is a
# cursor motion and would otherwise extend an existing range), runs the
# search, then writes the new index with set-option -F so the arithmetic is
# evaluated after the search moved the cursor. n always searches down and N
# always searches up, regardless of the original search direction. The index
# numbering does follow that direction, though: forward searches count from
# the top, backward searches from the bottom. So n adds one in a forward
# search but subtracts one in a backward search; N does the opposite. No shell
# and no client round trip.
cmh_pos='#{e|-|:#{e|+|:#{history_size},#{copy_cursor_y}},#{scroll_position}},#{copy_cursor_x}'
cmh_nav_gate="#{&&:#{@cmh_search_index},#{&&:#{@cmh_search_pos},#{&&:#{@cmh_search_dir},#{&&:#{search_count},#{&&:#{==:#{search_count_partial},0},#{&&:#{!=:#{search_timed_out},1},#{==:#{@cmh_search_pos},$cmh_pos}}}}}}}"

# bind_copy_mode_nav <key> <token> <search-flag>
bind_copy_mode_nav() {
  local key="$1" token="$2" sflag="$3"
  local raw wrap body fallback motion

  if ((!cmh_fast_keys)); then
    bind_copy_mode_key "$key" "$token"
    return
  fi
  case "$sflag" in
  again)
    # n: always down. search-again is down for a forward search and
    # search-reverse is down for a backward one.
    motion="if-shell -F '#{==:#{@cmh_search_dir},forward}' 'send-keys -X search-again' 'send-keys -X search-reverse'"
    raw='#{?#{==:#{@cmh_search_dir},forward},#{e|+|:#{@cmh_search_index},1},#{e|-|:#{@cmh_search_index},1}}'
    ;;
  reverse)
    # N: always up, the mirror of n.
    motion="if-shell -F '#{==:#{@cmh_search_dir},forward}' 'send-keys -X search-reverse' 'send-keys -X search-again'"
    raw='#{?#{==:#{@cmh_search_dir},forward},#{e|-|:#{@cmh_search_index},1},#{e|+|:#{@cmh_search_index},1}}'
    ;;
  esac
  wrap="#{?#{e|>:$raw,#{search_count}},1,#{?#{e|<:$raw,1},#{search_count},$raw}}"
  body="set-option -p @cmh_pending '' ; set-option -p @cmh_x_sel '' ; set-option -p @cmh_goal_col '' ; if-shell -F '$cmh_normal' 'send-keys -X clear-selection' ; $motion ; set-option -p -F @cmh_search_index '$wrap' ; set-option -p -F @cmh_search_pos '$cmh_pos' ; $cmh_repaint"

  printf -v fallback "run-shell \"bash '%s/keys.sh' %s '#{pane_id}'\"" "$SCRIPTS" "$token"
  tmux bind-key -T copy-mode-vi "$key" if-shell -F "$cmh_nav_gate" "$body" "$fallback"
}

# movement: j/k keep the dispatcher's verified column-repair fast path.
bind_copy_mode_key j j
bind_copy_mode_key k k
bind_copy_mode_key Down Down
bind_copy_mode_key Up Up
bind_copy_mode_fast h h clear-selection cursor-left
bind_copy_mode_fast l l clear-selection cursor-right
bind_copy_mode_fast Left Left clear-selection cursor-left
bind_copy_mode_fast Right Right clear-selection cursor-right

# words: normal mode selects the range the motion travels; extend mode grows
# the existing selection.
bind_copy_mode_fast w w begin-selection next-word
bind_copy_mode_fast e e begin-selection next-word-end
bind_copy_mode_fast b b begin-selection previous-word
bind_copy_mode_fast W W begin-selection next-space
bind_copy_mode_fast E E begin-selection next-space-end
bind_copy_mode_fast B B begin-selection previous-space

# line / buffer
bind_copy_mode_fast 0 0 clear-selection start-of-line
bind_copy_mode_fast Home Home clear-selection start-of-line
bind_copy_mode_fast '^' caret clear-selection back-to-indentation
bind_copy_mode_fast '$' dollar clear-selection end-of-line
bind_copy_mode_fast End End clear-selection end-of-line
bind_copy_mode_fast G G clear-selection history-bottom
bind_copy_mode_fast '{' leftbrace clear-selection previous-paragraph
bind_copy_mode_fast '}' rightbrace clear-selection next-paragraph
bind_copy_mode_fast ')' rightbrace clear-selection next-paragraph

# paging: C-d/C-u stay on the dispatcher because the half-page motion has to
# restore the cursor column after tmux resets it.
bind_copy_mode_key 'C-d' 'C-d'
bind_copy_mode_key 'C-u' 'C-u'
bind_copy_mode_fast 'C-f' 'C-f' clear-selection page-down
bind_copy_mode_fast 'C-b' 'C-b' clear-selection page-up
bind_copy_mode_fast NPage NPage clear-selection page-down
bind_copy_mode_fast PPage PPage clear-selection page-up

# prefixes: set @cmh_pending once; with a prefix already pending the gate
# sends the key to the dispatcher.
bind_copy_mode_fast g g '' '' g
bind_copy_mode_fast z z '' '' z
bind_copy_mode_fast m m '' '' m
bind_copy_mode_fast '[' lbracket '' '' prev
bind_copy_mode_fast ']' rbracket '' '' next

# Prefix-only second keys. With no prefix pending these are cursor no-ops that
# only perform the dispatcher's usual state housekeeping; with a prefix
# pending the gate sends them to the dispatcher (c/s/u/d are also plain
# keys.sh no-ops; binding them keeps tmux from handling them directly).
bind_copy_mode_fast c c '' '' ''
bind_copy_mode_fast s s '' '' ''
bind_copy_mode_fast u u '' '' ''
bind_copy_mode_fast d d '' '' ''
bind_copy_mode_fast p p '' '' ''

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
bind_copy_mode_nav n n again
bind_copy_mode_nav N N reverse
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

# find-char keys are dispatched through keys.sh too
bind_copy_mode_key f f
bind_copy_mode_key t t
bind_copy_mode_key F F
bind_copy_mode_key T T
