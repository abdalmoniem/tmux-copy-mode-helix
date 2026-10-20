#!/usr/bin/env bash
# move.sh <tmux-copy-command> <pane>
cmd="${1:-}"
pane="${2:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
mode="$(cmh_mode_get "$pane")"
if [[ "$mode" != "extend" ]]; then
  tmux send-keys -t "$pane" -X begin-selection
fi
tmux send-keys -t "$pane" -X "$cmd"
