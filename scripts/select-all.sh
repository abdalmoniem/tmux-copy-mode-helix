#!/usr/bin/env bash
# select-all.sh <pane>   (Helix: % = select entire buffer)
pane="${1:-}"
[ -z "$pane" ] && exit 0
tmux send-keys -t "$pane" -X history-top
tmux send-keys -t "$pane" -X begin-selection
tmux send-keys -t "$pane" -X history-bottom
