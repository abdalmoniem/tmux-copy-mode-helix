#!/usr/bin/env bash
# unimp-prev.sh <pane> <key>   (Helix '[')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
DIR="${0%/*}"
case "$key" in
  p) "$DIR/move.sh" previous-paragraph "$pane" ;;
  *) tmux display-message -t "$pane" "copy-mode-helix: unsupported '[' key '$key'" ;;
esac
