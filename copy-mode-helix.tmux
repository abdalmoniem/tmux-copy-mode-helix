#!/usr/bin/env bash
# copy-mode-helix.tmux -- TPM entry point
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$CURRENT_DIR/scripts"

# --- clipboard detection ------------------------------------------------------
CLIP="cat > /dev/null"
if command -v wl-copy >/dev/null 2>&1; then
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
# Use the vi copy-mode table (re-mapped to Helix motions below).
tmux set-window-option -g mode-keys vi >/dev/null 2>&1

# --- enter copy mode ---------------------------------------------------------
tmux bind-key [ run-shell -b "$SCRIPTS/enter-copy-mode.sh '#{pane_id}'"

b() { # helper: bind a simple motion key to move.sh
  # $1 tmux key spec, $2 tmux copy command
  tmux bind-key -T copy-mode-vi "$1" run-shell -b "$SCRIPTS/move.sh '$2' '#{pane_id}'"
}

# basic movement
b h   cursor-left
b j   cursor-down
b k   cursor-up
b l   cursor-right
b Left  cursor-left
b Down  cursor-down
b Up    cursor-up
b Right cursor-right

# word motions
b w   next-word
b e   next-word-end
b b   previous-word
b W   next-space
b E   next-space-end
b B   previous-space

# line / buffer motions
b 0       start-of-line
b Home    start-of-line
b '^'     back-to-indentation
b '$'     end-of-line
b End     end-of-line
b G       history-bottom
b '{'     previous-paragraph
b '}'     next-paragraph

# paging / scrolling
b 'C-d'   halfpage-down
b 'C-u'   halfpage-up
b 'C-f'   page-down
b 'C-b'   page-up
b NPage   page-down
b PPage   page-up

# selection helpers
b o       other-end
b n       search-again
b N       search-reverse
b '\;'    clear-selection
b ','     jump-reverse

# --- select / extend mode ----------------------------------------------------
tmux bind-key -T copy-mode-vi v run-shell -b "$SCRIPTS/toggle-mode.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi Space run-shell -b "$SCRIPTS/toggle-mode.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi x run-shell -b "$SCRIPTS/select-line.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi X run-shell -b "$SCRIPTS/select-line.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi V run-shell -b "$SCRIPTS/select-line.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi '%' run-shell -b "$SCRIPTS/select-all.sh '#{pane_id}'"

# --- view / match / goto / unimpaired via prompts ----------------------------
tmux bind-key -T copy-mode-vi g command-prompt -1 -p "(goto)" \
  "run-shell -b '$SCRIPTS/goto-mode.sh #{pane_id} %%'"

tmux bind-key -T copy-mode-vi z command-prompt -1 -p "(view)" \
  "run-shell -b '$SCRIPTS/view-mode.sh #{pane_id} %%'"

tmux bind-key -T copy-mode-vi Z command-prompt -1 -p "(view)" \
  "run-shell -b '$SCRIPTS/view-mode.sh #{pane_id} %%'"

tmux bind-key -T copy-mode-vi m command-prompt -1 -p "(match)" \
  "run-shell -b '$SCRIPTS/match-mode.sh #{pane_id} %%'"

tmux bind-key -T copy-mode-vi '[' command-prompt -1 -p "(prev)" \
  "run-shell -b '$SCRIPTS/unimp-prev.sh #{pane_id} %%'"

tmux bind-key -T copy-mode-vi ']' command-prompt -1 -p "(next)" \
  "run-shell -b '$SCRIPTS/unimp-next.sh #{pane_id} %%'"

# --- find char ----------------------------------------------------------------
tmux bind-key -T copy-mode-vi f command-prompt -1 -p "(find)" \
  "run-shell -b '$SCRIPTS/find-char.sh jump-forward #{pane_id} %%'"

tmux bind-key -T copy-mode-vi t command-prompt -1 -p "(till)" \
  "run-shell -b '$SCRIPTS/find-char.sh jump-to-forward #{pane_id} %%'"

tmux bind-key -T copy-mode-vi F command-prompt -1 -p "(find back)" \
  "run-shell -b '$SCRIPTS/find-char.sh jump-backward #{pane_id} %%'"

tmux bind-key -T copy-mode-vi T command-prompt -1 -p "(till back)" \
  "run-shell -b '$SCRIPTS/find-char.sh jump-to-backward #{pane_id} %%'"

# --- search ------------------------------------------------------------------
tmux bind-key -T copy-mode-vi / command-prompt -T search -p "(search down)" \
  "run-shell -b '$SCRIPTS/search.sh forward #{pane_id} %%'"

tmux bind-key -T copy-mode-vi '?' command-prompt -T search -p "(search up)" \
  "run-shell -b '$SCRIPTS/search.sh backward #{pane_id} %%'"

tmux bind-key -T copy-mode-vi '*' send-keys -X search-forward -- "#{copy_cursor_word}"
tmux bind-key -T copy-mode-vi '#' send-keys -X search-backward -- "#{copy_cursor_word}"

# goto line
tmux bind-key -T copy-mode-vi ':' command-prompt -p "(goto line)" \
  "send-keys -X goto-line -- '%%'"

# --- yank / copy -------------------------------------------------------------
tmux bind-key -T copy-mode-vi y run-shell -b "$SCRIPTS/yank.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi Enter run-shell -b "$SCRIPTS/yank.sh '#{pane_id}'"
tmux bind-key -T copy-mode-vi Y run-shell -b "$SCRIPTS/yank-line.sh '#{pane_id}'"

# --- misc --------------------------------------------------------------------
tmux bind-key -T copy-mode-vi r send-keys -X refresh-from-pane
tmux bind-key -T copy-mode-vi q send-keys -X cancel
tmux bind-key -T copy-mode-vi Escape send-keys -X clear-selection
