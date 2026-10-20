#!/usr/bin/env bash
# goto-mode.sh <pane> <key>   (everything under Helix 'g')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
case "$key" in
  g) "${0%/*}/move.sh" history-top "$pane" ;;
  e) "${0%/*}/move.sh" history-bottom "$pane" ;;
  h) "${0%/*}/move.sh" start-of-line "$pane" ;;
  l) "${0%/*}/move.sh" end-of-line "$pane" ;;
  s) "${0%/*}/move.sh" back-to-indentation "$pane" ;;
  t) tmux send-keys -t "$pane" -X top-line ;;
  c) tmux send-keys -t "$pane" -X middle-line ;;
  b) tmux send-keys -t "$pane" -X bottom-line ;;
  j) "${0%/*}/move.sh" cursor-down "$pane" ;;
  k) "${0%/*}/move.sh" cursor-up "$pane" ;;
  w) cmh_alert "$pane" 'helix goto-word is not available in tmux' ;;
  *) cmh_alert "$pane" "unknown goto key '$key'" ;;
esac
