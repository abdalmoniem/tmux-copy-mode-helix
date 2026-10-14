#!/usr/bin/env bash
# yank-line.sh <pane>
pane="${1:-}"
[ -z "$pane" ] && exit 0
. "${0%/*}/common.sh"
# Select the whole current line, then yank it.
tmux send-keys -t "$pane" -X start-of-line
tmux send-keys -t "$pane" -X begin-selection
tmux send-keys -t "$pane" -X end-of-line
clip="$(cmh_clip_get)"
tmux send-keys -t "$pane" -X copy-pipe-and-cancel "$clip"
tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
