#!/usr/bin/env bash
pane="${1:-}"
[ -z "$pane" ] && exit 0
tmux copy-mode -t "$pane"
tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
tmux set-option -p -t "$pane" @cmh_keys '' >/dev/null 2>&1
tmux set-option -p -t "$pane" @cmh_pending '' >/dev/null 2>&1
