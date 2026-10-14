#!/usr/bin/env bash
# Shared helpers for copy-mode-helix.
# $1 is always the pane id unless otherwise documented.

pane_id() { printf '%s' "${1:-}"; }

cmh_mode_get() {
  local pane="${1:-}"
  tmux show-option -pv -t "$pane" @cmh_mode 2>/dev/null || printf 'normal'
}

cmh_clip_get() {
  tmux show-option -gv @cmh_clip 2>/dev/null || printf 'cat > /dev/null'
}

cmh_begin_if_normal() {
  local pane="${1:-}"
  local mode
  mode="$(cmh_mode_get "$pane")"
  if [[ "$mode" != "extend" ]]; then
    tmux send-keys -t "$pane" -X begin-selection
  fi
}
