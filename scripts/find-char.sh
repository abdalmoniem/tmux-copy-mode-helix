#!/usr/bin/env bash
# find-char.sh <command> <pane> <char>
# command: jump-forward | jump-to-forward | jump-backward | jump-to-backward
cmd="${1:-}"
pane="${2:-}"
char="${3:-}"
[ -z "$pane" ] && exit 0
if [[ -z "$char" ]]; then
  # Prompt input is stored in a pane option so command-prompt's template
  # parser cannot eat a literal backslash.
  char="$(tmux show-option -pv -t "$pane" @cmh_find_char 2>/dev/null || true)"
  tmux set-option -pu -t "$pane" @cmh_find_char >/dev/null 2>&1
fi
source "${0%/*}/common.sh"
cmh_begin_if_normal "$pane"
tmux send-keys -t "$pane" -X "$cmd" -- "$char"
