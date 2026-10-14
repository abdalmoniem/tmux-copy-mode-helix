#!/usr/bin/env bash
# select-line.sh <pane>   (Helix: x = select current line)
pane="${1:-}"
[ -z "$pane" ] && exit 0
tmux send-keys -t "$pane" -X select-line
tmux set-option -p -t "$pane" @cmh_mode extend >/dev/null 2>&1
