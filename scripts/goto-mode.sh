#!/usr/bin/env bash
# goto-mode.sh <pane> <key>   (everything under Helix 'g')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
DIR="${0%/*}"
case "$key" in
  g) "$DIR/move.sh" history-top "$pane" ;;
  e) "$DIR/move.sh" history-bottom "$pane" ;;
  h) "$DIR/move.sh" start-of-line "$pane" ;;
  l) "$DIR/move.sh" end-of-line "$pane" ;;
  s) "$DIR/move.sh" back-to-indentation "$pane" ;;
  t) tmux send-keys -t "$pane" -X top-line ;;
  c) tmux send-keys -t "$pane" -X middle-line ;;
  b) tmux send-keys -t "$pane" -X bottom-line ;;
  j) "$DIR/move.sh" cursor-down "$pane" ;;
  k) "$DIR/move.sh" cursor-up "$pane" ;;
  w) tmux display-message -t "$pane" 'helix goto-word is not available in tmux' ;;
  *) tmux display-message -t "$pane" "copy-mode-helix: unknown goto key '$key'" ;;
esac
