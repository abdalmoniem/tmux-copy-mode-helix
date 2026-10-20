#!/usr/bin/env bash
# Shared helpers for copy-mode-helix.
# $1 is always the pane id unless otherwise documented.

pane_id() { printf '%s' "${1:-}"; }

cmh_mode_get() {
  local pane="${1:-}"
  tmux show-option -pv -t "$pane" @cmh_mode 2>/dev/null || printf 'normal'
}

cmh_clip_get() {
  tmux show-option -gv @cmh_clip 2>/dev/null || true
}

cmh_alert() {  # $1 = pane id, $2 = text
 tmux display-message -d 4000 -t "${1:-}" \
   "#[bg=red,fg=white,bold] copy-mode-helix: ${2:-} #[default]"
}

# Resolve the clipboard command for a yank, or fail loudly.
# $1 = pane id. Prints the command on success. On failure it reports on that
# pane's status line and returns 1 so the caller skips copy-pipe entirely: a
# bogus or missing command must never look like a successful yank, and yanks
# run copy-pipe with -C, so tmux's OSC 52 path cannot quietly do it instead.
cmh_clip_or_die() {
  local pane="${1:-}" clip word
  clip="$(cmh_clip_get)"
  word="${clip%% *}"
  if [[ -z "$word" ]]; then
    cmh_alert "$pane" "no clipboard command configured (set @copy-mode-helix-clipboard)"
    return 1
  fi
  if ! command -v "$word" >/dev/null 2>&1; then
    cmh_alert "$pane" "clipboard command not found: $word"
    return 1
  fi
  printf '%s' "$clip"
}

cmh_begin_if_normal() {
  local pane="${1:-}"
  local mode
  mode="$(cmh_mode_get "$pane")"
  if [[ "$mode" != "extend" ]]; then
    tmux send-keys -t "$pane" -X begin-selection
  fi
}

cmh_restore_status() {
  local prev
  prev="$(tmux show-option -gv @cmh_prev_status 2>/dev/null || printf on)"
  tmux set-option -g status "$prev" >/dev/null 2>&1
  tmux set-option -gu @cmh_prev_status >/dev/null 2>&1
}
