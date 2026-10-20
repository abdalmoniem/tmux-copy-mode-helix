#!/usr/bin/env bash
# find-char.sh <command> <pane> <char>
# command: jump-forward | jump-to-forward | jump-backward | jump-to-backward
cmd="${1:-}"
pane="${2:-}"
char="${3:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
cmh_begin_if_normal "$pane"
tmux send-keys -t "$pane" -X "$cmd" -- "$char"
