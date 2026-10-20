#!/usr/bin/env bash
# yank.sh <pane>
pane="${1:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
clip="$(cmh_clip_or_die "$pane")" || exit 0
tmux send-keys -t "$pane" -X copy-pipe-and-cancel -C "$clip"
tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
