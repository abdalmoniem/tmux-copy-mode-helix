#!/usr/bin/env bash
# view-mode.sh <pane> <key>   (everything under Helix 'z')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
case "$key" in
  z|c) tmux send-keys -t "$pane" -X scroll-middle ;;
  t)   tmux send-keys -t "$pane" -X scroll-top ;;
  b)   tmux send-keys -t "$pane" -X scroll-bottom ;;
  j)   tmux send-keys -t "$pane" -X scroll-down ;;
  k)   tmux send-keys -t "$pane" -X scroll-up ;;
  u)   tmux send-keys -t "$pane" -X halfpage-up ;;
  d)   tmux send-keys -t "$pane" -X halfpage-down ;;
  *)   cmh_alert "$pane" "unknown view key '$key'" ;;
esac
