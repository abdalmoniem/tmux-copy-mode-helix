#!/usr/bin/env bash
# search.sh <direction> <pane> <pattern>
direction="${1:-}"
pane="${2:-}"
pattern="${3:-}"
[ -z "$pane" ] && exit 0
if [[ "$direction" == "backward" ]]; then
  tmux send-keys -t "$pane" -X search-backward -- "$pattern"
else
  tmux send-keys -t "$pane" -X search-forward -- "$pattern"
fi
