#!/usr/bin/env bash
# view-mode.sh <pane> <key>   (everything under Helix 'z')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
case "$key" in
  z|c) tmux send-keys -t "$pane" -X scroll-middle ;;
  t)   tmux send-keys -t "$pane" -X scroll-top ;;
  b)   tmux send-keys -t "$pane" -X scroll-bottom ;;
  j)   tmux send-keys -t "$pane" -X scroll-down ;;
  k)   tmux send-keys -t "$pane" -X scroll-up ;;
  u)   tmux send-keys -t "$pane" -X halfpage-up ;;
  d)   tmux send-keys -t "$pane" -X halfpage-down ;;
  *)   tmux display-message -t "$pane" "copy-mode-helix: unknown view key '$key'" ;;
esac
