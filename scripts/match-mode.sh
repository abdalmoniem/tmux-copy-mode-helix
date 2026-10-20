#!/usr/bin/env bash
# match-mode.sh <pane> <key>   (everything under Helix 'm')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
case "$key" in
  m)
    source "${0%/*}/common.sh"
    cmh_begin_if_normal "$pane"
    tmux send-keys -t "$pane" -X next-matching-bracket
    ;;
  a|i)
    cmh_alert "$pane" 'text-objects need tree-sitter (not available in tmux)'
    ;;
  s|r|d)
    cmh_alert -t "$pane" 'surround/edit ops are not copy-mode actions'
    ;;
  *)
    cmh_alert -t "$pane" "unknown match key '$key'"
    ;;
esac
