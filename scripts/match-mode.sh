#!/usr/bin/env bash
# match-mode.sh <pane> <key>   (everything under Helix 'm')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
DIR="${0%/*}"
case "$key" in
  m)
    . "$DIR/common.sh"
    cmh_begin_if_normal "$pane"
    tmux send-keys -t "$pane" -X next-matching-bracket
    ;;
  a|i)
    tmux display-message -t "$pane" 'copy-mode-helix: text-objects need tree-sitter (not available in tmux)'
    ;;
  s|r|d)
    tmux display-message -t "$pane" 'copy-mode-helix: surround/edit ops are not copy-mode actions'
    ;;
  *)
    tmux display-message -t "$pane" "copy-mode-helix: unknown match key '$key'"
    ;;
esac
