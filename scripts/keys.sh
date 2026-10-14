#!/usr/bin/env bash
# Unified Helix key dispatcher for tmux copy mode.
# keys.sh <key-token> <pane>
key="${1:-}"
pane="${2:-}"
[ -z "$pane" ] && exit 0
. "${0%/*}/common.sh"

# reset repeated-x state unless this key reuses it
if [[ "$key" != "x" && "$key" != "X" && "$key" != "V" ]]; then
  tmux set-option -p -t "$pane" @cmh_x_origin '' >/dev/null 2>&1
  tmux set-option -p -t "$pane" @cmh_x_count '' >/dev/null 2>&1
fi

pending="$(tmux show-option -pv -t "$pane" @cmh_pending 2>/dev/null || printf '')"
m="$(cmh_mode_get "$pane")"

motion() {
  if [[ "$m" == "extend" ]]; then
    tmux send-keys -t "$pane" -X "$1"
  else
    case "$key" in
      w|W|e|E|b|B)
        # normal-mode word motion selects its travelled range
        tmux send-keys -t "$pane" -X begin-selection
        tmux send-keys -t "$pane" -X "$1"
        ;;
      *)
        # single-char movement clears current selection and does not select
        tmux send-keys -t "$pane" -X clear-selection
        tmux send-keys -t "$pane" -X "$1"
        ;;
    esac
  fi
}

clear_pending() { tmux set-option -p -t "$pane" @cmh_pending '' >/dev/null 2>&1; }
set_pending() { tmux set-option -p -t "$pane" @cmh_pending "${1:-}" >/dev/null 2>&1; }
begin_normal() {
  if [[ "$m" != "extend" ]]; then
    tmux send-keys -t "$pane" -X begin-selection
  fi
}

# ---- handle pending prefix combinations ------------------------------------
if [[ -n "$pending" ]]; then
  case "${pending}-${key}" in
    g-g)
      clear_pending; key=goto motion history-top; exit 0 ;;
    g-e)
      clear_pending; key=goto motion history-bottom; exit 0 ;;
    g-h)
      clear_pending; key=goto motion start-of-line; exit 0 ;;
    g-l)
      clear_pending; key=goto motion end-of-line; exit 0 ;;
    g-s)
      clear_pending; key=goto motion back-to-indentation; exit 0 ;;
    g-t)
      clear_pending; tmux send-keys -t "$pane" -X top-line; exit 0 ;;
    g-c)
      clear_pending; tmux send-keys -t "$pane" -X middle-line; exit 0 ;;
    g-b)
      clear_pending; tmux send-keys -t "$pane" -X bottom-line; exit 0 ;;
    g-j)
      clear_pending; key=goto motion cursor-down; exit 0 ;;
    g-k)
      clear_pending; key=goto motion cursor-up; exit 0 ;;
    g-w)
      clear_pending; tmux display-message -t "$pane" 'copy-mode-helix: goto-word needs tree-sitter'; exit 0 ;;

    z-z|z-c)
      clear_pending; tmux send-keys -t "$pane" -X scroll-middle; exit 0 ;;
    z-t)
      clear_pending; tmux send-keys -t "$pane" -X scroll-top; exit 0 ;;
    z-b)
      clear_pending; tmux send-keys -t "$pane" -X scroll-bottom; exit 0 ;;
    z-j)
      clear_pending; tmux send-keys -t "$pane" -X scroll-down; exit 0 ;;
    z-k)
      clear_pending; tmux send-keys -t "$pane" -X scroll-up; exit 0 ;;
    z-u)
      clear_pending; tmux send-keys -t "$pane" -X halfpage-up; exit 0 ;;
    z-d)
      clear_pending; tmux send-keys -t "$pane" -X halfpage-down; exit 0 ;;

    m-m)
      clear_pending
      . "${0%/*}/common.sh"
      cmh_begin_if_normal "$pane"
      tmux send-keys -t "$pane" -X next-matching-bracket
      exit 0 ;;

    prev-p)
      clear_pending; key=goto motion previous-paragraph; exit 0 ;;
    next-p)
      clear_pending; key=goto motion next-paragraph; exit 0 ;;
  esac
  # unknown combination: clear pending and fall through
  clear_pending
fi

# ---- normal key handling ---------------------------------------------------
case "$key" in
  h|Left) motion cursor-left ;;
  j|Down) motion cursor-down ;;
  k|Up) motion cursor-up ;;
  l|Right) motion cursor-right ;;

  w) motion next-word ;;
  e) motion next-word-end ;;
  b) motion previous-word ;;
  W) motion next-space ;;
  E) motion next-space-end ;;
  B) motion previous-space ;;

  0|Home) motion start-of-line ;;
  caret) motion back-to-indentation ;;
  dollar|End) motion end-of-line ;;
  G) motion history-bottom ;;
  leftbrace) motion previous-paragraph ;;
  rightbrace) motion next-paragraph ;;
  C-d) motion halfpage-down ;;
  C-u) motion halfpage-up ;;
  C-f) motion page-down ;;
  C-b) motion page-up ;;
  NPage) motion page-down ;;
  PPage) motion page-up ;;

  comma) tmux send-keys -t "$pane" -X jump-reverse ;;
  semicolon) tmux send-keys -t "$pane" -X clear-selection ;;
  o) tmux send-keys -t "$pane" -X other-end ;;
  n) tmux send-keys -t "$pane" -X search-again ;;
  N) tmux send-keys -t "$pane" -X search-reverse ;;
  r) tmux send-keys -t "$pane" -X refresh-from-pane ;;

  v|space)
    tmux set-option -p -t "$pane" @cmh_x_origin '' >/dev/null 2>&1
    tmux set-option -p -t "$pane" @cmh_x_count '' >/dev/null 2>&1
    if [[ "$m" == "extend" ]]; then
      tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
      m='normal'
      tmux send-keys -t "$pane" -X other-end
      tmux send-keys -t "$pane" -X other-end
    else
      tmux set-option -p -t "$pane" @cmh_mode extend >/dev/null 2>&1
      m='extend'
      tmux send-keys -t "$pane" -X other-end
      tmux send-keys -t "$pane" -X other-end
      active="$(tmux display -p -t "$pane" '#{selection_active}' 2>/dev/null || printf 0)"
      if [[ "$active" != "1" ]]; then
        tmux send-keys -t "$pane" -X begin-selection
      fi
    fi
    ;;
  x|X|V)
    # Reset x-state on any non-x key is handled before dispatch; here extend by
    # line on repeated press, matching helix 'x'.
    cur_origin="$(tmux show-option -pv -t "$pane" @cmh_x_origin 2>/dev/null || true)"
    cur_count="$(tmux show-option -pv -t "$pane" @cmh_x_count 2>/dev/null || true)"
    if [[ -z "$cur_origin" || "$cur_count" == "" ]]; then
      cur_origin="$(tmux display -p -t "$pane" '#{cursor_y}')"
      tmux send-keys -t "$pane" -X start-of-line
      tmux send-keys -t "$pane" -X begin-selection
      tmux send-keys -t "$pane" -X end-of-line
      cur_count=1
    else
      # extend to the next line below by rebuilding the selection
      move_up=$((cur_count - 1))
      if [[ $move_up -gt 0 ]]; then
        tmux send-keys -t "$pane" -X -N "$move_up" cursor-up
      fi
      tmux send-keys -t "$pane" -X clear-selection
      tmux send-keys -t "$pane" -X start-of-line
      tmux send-keys -t "$pane" -X begin-selection
      if [[ $cur_count -gt 1 ]]; then
        tmux send-keys -t "$pane" -X -N "$((cur_count - 1))" cursor-down
      fi
      tmux send-keys -t "$pane" -X cursor-down
      tmux send-keys -t "$pane" -X end-of-line
      cur_count=$((cur_count + 1))
    fi
    tmux set-option -p -t "$pane" @cmh_x_origin "$cur_origin" >/dev/null 2>&1
    tmux set-option -p -t "$pane" @cmh_x_count "$cur_count" >/dev/null 2>&1
    tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
    m='normal'
    ;;

  percent)
    tmux send-keys -t "$pane" -X history-top
    tmux send-keys -t "$pane" -X begin-selection
    tmux send-keys -t "$pane" -X history-bottom
    ;;
  y|Enter)
    . "${0%/*}/common.sh"
    clip="$(cmh_clip_get)"
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel "$clip"
    tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
    ;;
  Y)
    . "${0%/*}/common.sh"
    tmux send-keys -t "$pane" -X start-of-line
    tmux send-keys -t "$pane" -X begin-selection
    tmux send-keys -t "$pane" -X end-of-line
    clip="$(cmh_clip_get)"
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel "$clip"
    tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
    ;;
  asterisk)
    tmux send-keys -t "$pane" -X search-forward -- "#{copy_cursor_word}" ;;
  hash)
    tmux send-keys -t "$pane" -X search-backward -- "#{copy_cursor_word}" ;;

  # begin a minor mode / prefix
  g) set_pending "g"; tmux set-option -p -t "$pane" @cmh_pending "g" ;;
  z) set_pending "z" ;;
  m) set_pending "m" ;;
  lbracket) set_pending "prev" ;;
  rbracket) set_pending "next" ;;

  # prompt-based commands
  f)
    tmux command-prompt -1 -p "(find)" "run-shell -b '${0%/*}/find-char.sh jump-forward #{pane_id} %%'" ;;
  t)
    tmux command-prompt -1 -p "(till)" "run-shell -b '${0%/*}/find-char.sh jump-to-forward #{pane_id} %%'" ;;
  F)
    tmux command-prompt -1 -p "(find back)" "run-shell -b '${0%/*}/find-char.sh jump-backward #{pane_id} %%'" ;;
  T)
    tmux command-prompt -1 -p "(till back)" "run-shell -b '${0%/*}/find-char.sh jump-to-backward #{pane_id} %%'" ;;
  slash)
    tmux command-prompt -T search -p "(search down)" "run-shell -b '${0%/*}/search.sh forward #{pane_id} %%'" ;;
  question)
    tmux command-prompt -T search -p "(search up)" "run-shell -b '${0%/*}/search.sh backward #{pane_id} %%'" ;;
  colon)
    tmux command-prompt -p "(goto line)" "send-keys -X goto-line -- '%%'" ;;

  q|Escape)
    tmux set-option -p -t "$pane" @cmh_x_origin '' >/dev/null 2>&1
    tmux set-option -p -t "$pane" @cmh_x_count '' >/dev/null 2>&1
    mode_now="$(cmh_mode_get "$pane")"
    if [[ "$mode_now" == "extend" ]]; then
      # Collapse to normal mode without leaving copy mode.
      tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
      m='normal'
      tmux send-keys -t "$pane" -X other-end
      tmux send-keys -t "$pane" -X other-end
      tmux send-keys -t "$pane" -X clear-selection
    else
      tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
      tmux send-keys -t "$pane" -X cancel
    fi
    ;;
  *)
    tmux display-message -t "$pane" "copy-mode-helix: unbound key '$key'" ;;
esac
# clear pending if a normal command ran (prefix keys set it above)
case "$key" in g|z|m|lbracket|rbracket) ;; *) clear_pending ;; esac
