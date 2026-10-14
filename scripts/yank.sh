#!/usr/bin/env bash
# yank.sh <pane>
pane="${1:-}"
[ -z "$pane" ] && exit 0
. "${0%/*}/common.sh"
clip="$(cmh_clip_get)"
tmux send-keys -t "$pane" -X copy-pipe-and-cancel "$clip"
tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
