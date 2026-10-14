#!/usr/bin/env bash
# toggle-mode.sh <pane>
pane="${1:-}"
[ -z "$pane" ] && exit 0
. "${0%/*}/common.sh"
mode="$(cmh_mode_get "$pane")"
if [[ "$mode" == "extend" ]]; then
  tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
  tmux send-keys -t "$pane" -X clear-selection
else
  tmux set-option -p -t "$pane" @cmh_mode extend >/dev/null 2>&1
  tmux send-keys -t "$pane" -X begin-selection
fi
