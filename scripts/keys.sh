#!/usr/bin/env bash
# Unified Helix key dispatcher for tmux copy mode.
# keys.sh <key-token> <pane>
key="${1:-}"
pane="${2:-}"
[ -z "$pane" ] && exit 0
. "${0%/*}/common.sh"

# Read pending/mode/x/search state and the cursor in one tmux call. '|'
# preserves empty fields.
IFS='|' read -r pending m xsel sindex spos sdir hsize oy cy cx < <(tmux display -p -t "$pane" \
  '#{@cmh_pending}|#{@cmh_mode}|#{@cmh_x_sel}|#{@cmh_search_index}|#{@cmh_search_pos}|#{@cmh_search_dir}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}' \
  2>/dev/null)
m="${m:-normal}"
hsize="${hsize:-0}"; oy="${oy:-0}"; cy="${cy:-0}"; cx="${cx:-0}"

# Only x/X/V and keys that leave the selection untouched may reuse the
# x-owned selection state; everything else starts a fresh x range.
case "$key" in
  x|X|V|o|v|space) ;;
  *) [[ -n "$xsel" ]] && tmux set-option -p -t "$pane" @cmh_x_sel '' >/dev/null 2>&1 ;;
esac

# @cmh_search_index names the match under the cursor; any key other than search
# navigation moves off it, so drop the index (the total stays visible).
case "$key" in
  n|N|asterisk|hash) ;;
  *) [[ -n "$sindex$spos" ]] && tmux set-option -p -t "$pane" @cmh_search_index '' \; set-option -p -t "$pane" @cmh_search_pos '' >/dev/null 2>&1 ;;
esac

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

# Search result tracking: @cmh_search_index is the 1-based number of the match
# under the cursor, @cmh_search_pos where it was counted. tmux knows only the
# total (search_count), so search-index.sh counts the rest.
cmh_search_set() {
  tmux set-option -p -t "$pane" @cmh_search_index "${1:-}" \; \
       set-option -p -t "$pane" @cmh_search_pos "${2:-}" >/dev/null 2>&1
}
cmh_search_begin() {
  tmux set-option -p -t "$pane" @cmh_search_pattern "${1:-}" \; \
       set-option -p -t "$pane" @cmh_search_regex "${2:-}" \; \
       set-option -p -t "$pane" @cmh_search_dir "${3:-}" \; \
       set-option -p -t "$pane" @cmh_search_index '' \; \
       set-option -p -t "$pane" @cmh_search_pos '' >/dev/null 2>&1
}

# Move the cursor half a viewport, keeping its column. tmux's halfpage-* commands
# reset the column and can leave partial selections behind.
cmh_halfpage() {
  local dir="$1" n height cx
  read -r cx height <<< "$(tmux display -p -t "$pane" '#{copy_cursor_x} #{pane_height}' 2>/dev/null || printf '0 1')"
  height="${height:-1}"
  (( height < 1 )) && height=1
  n=$(( height / 2 ))
  (( n < 1 )) && n=1
  if [[ "$m" != "extend" ]]; then
    tmux send-keys -t "$pane" -X clear-selection
  fi
  # Nudge left before a vertical move so tmux remembers the current column
  # instead of substituting a stale one, then restore the column afterwards.
  # Unlike start-of-line, this keeps the motion on visual rows when lines wrap.
  if (( cx > 0 )); then
    tmux send-keys -t "$pane" -X cursor-left
  fi
  if [[ "$dir" == "up" ]]; then
    tmux send-keys -t "$pane" -X -N "$n" cursor-up
  else
    tmux send-keys -t "$pane" -X -N "$n" cursor-down
  fi
  if (( cx > 0 )); then
    tmux send-keys -t "$pane" -X cursor-right
  fi
}

# Move the cursor to the top/middle/bottom visible row, then restore its
# column. top-line/middle-line/bottom-line reset the column to 0.
cmh_goto_window_row() {
  local target="$1" cx
  read -r cx <<< "$(tmux display -p -t "$pane" '#{copy_cursor_x}' 2>/dev/null || printf '0')"
  if [[ "$m" != "extend" ]]; then
    tmux send-keys -t "$pane" -X clear-selection
  fi
  case "$target" in
    top) tmux send-keys -t "$pane" -X top-line ;;
    middle) tmux send-keys -t "$pane" -X middle-line ;;
    bottom) tmux send-keys -t "$pane" -X bottom-line ;;
  esac
  if (( cx > 0 )); then
    tmux send-keys -t "$pane" -X -N "$cx" cursor-right
  fi
}

# Expand/advance the active selection in place.  "extend" is 1 to add the line
# below, 0 to only expand the existing range to line boundaries. This moves the
# selection endpoints directly, so repeated x never walks lines or re-anchors.
cmh_x_adjust_selection() {
  local extend="$1"
  local xsx xsy xex xey xcx xcy xhsize xoy cur lx ly hx hy ctl

  read -r xsx xsy xex xey xcx xcy xhsize xoy <<< "$(tmux display -p -t "$pane" \
    '#{selection_start_x} #{selection_start_y} #{selection_end_x} #{selection_end_y} #{copy_cursor_x} #{copy_cursor_y} #{history_size} #{scroll_position}' \
    2>/dev/null || printf '0 0 0 0 0 0 0 0')"
  cur=$(( xhsize - xoy + xcy ))

  if (( xsy < xey || (xsy == xey && xsx <= xex) )); then
    lx=$xsx; ly=$xsy; hx=$xex; hy=$xey
  else
    lx=$xex; ly=$xey; hx=$xsx; hy=$xsy
  fi

  # Which end is the cursor currently moving?
  if [[ "$xcx,$cur" == "$lx,$ly" && "$xcx,$cur" != "$hx,$hy" ]]; then
    ctl=low
  elif [[ "$xcx,$cur" == "$hx,$hy" ]]; then
    ctl=high
  elif (( cur == ly )); then
    ctl=low
  else
    ctl=high
  fi

  # Arbitrary selections get expanded to whole lines first. x-owned ranges are
  # already line-aligned, so skip this and only move the bottom end. If the
  # lower end already starts at column 0, avoid jumping the view to it.
  if [[ "$extend" != "1" && "$lx" != "0" ]]; then
    if [[ "$ctl" != "low" ]]; then
      tmux send-keys -t "$pane" -X other-end
    fi
    tmux send-keys -t "$pane" -X start-of-line
    tmux send-keys -t "$pane" -X other-end
    ctl=high
  fi

  if [[ "$ctl" != "high" ]]; then
    tmux send-keys -t "$pane" -X other-end
  fi

  if [[ "$extend" == "1" ]]; then
    tmux send-keys -t "$pane" -X end-of-line
    tmux send-keys -t "$pane" -X cursor-down
  fi
  tmux send-keys -t "$pane" -X end-of-line
}

cmh_selection_signature() {
  tmux display -p -t "$pane" '#{selection_start_x},#{selection_start_y},#{selection_end_x},#{selection_end_y}' 2>/dev/null || true
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
      clear_pending; cmh_goto_window_row top; exit 0 ;;
    g-c)
      clear_pending; cmh_goto_window_row middle; exit 0 ;;
    g-b)
      clear_pending; cmh_goto_window_row bottom; exit 0 ;;
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
      clear_pending; cmh_halfpage up; exit 0 ;;
    z-d)
      clear_pending; cmh_halfpage down; exit 0 ;;

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
  # second keys for g/z/[/] prefixes; handled above when a prefix is pending
  c|s|u|d|p) ;;
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
  C-d) cmh_halfpage down ;;
  C-u) cmh_halfpage up ;;
  C-f) motion page-down ;;
  C-b) motion page-up ;;
  NPage) motion page-down ;;
  PPage) motion page-up ;;

  comma) tmux send-keys -t "$pane" -X jump-reverse ;;
  semicolon)
    # Helix's ';' collapses the selection to the cursor. In SEL mode keep a
    # zero-width anchor so the next motion starts selecting from here instead
    # of moving around with a stale "extend" mode and no selection.
    tmux send-keys -t "$pane" -X clear-selection
    if [[ "$m" == "extend" ]]; then
      tmux send-keys -t "$pane" -X begin-selection
    fi
    ;;
  o) tmux send-keys -t "$pane" -X other-end ;;
  n|N)
    # Reuse the recorded index when the cursor still sits on the match it was
    # counted for; otherwise recount from the buffer.
    cur="$(( hsize - oy + cy )),$cx"
    cheap=0
    [[ "$sindex" =~ ^[0-9]+$ && "$spos" == "$cur" && -n "$sdir" ]] && cheap=1
    if [[ "$key" == "n" ]]; then
      tmux send-keys -t "$pane" -X search-again
    else
      tmux send-keys -t "$pane" -X search-reverse
    fi
    IFS='|' read -r total partial nh no ncy ncx < <(tmux display -p -t "$pane" \
      '#{search_count}|#{search_count_partial}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}' \
      2>/dev/null)
    if [[ -z "${total:-}" ]]; then
      cmh_search_set '' ''
    elif (( cheap )); then
      ni="$sindex"
      if [[ ( "$sdir" == "forward" && "$key" == "n" ) || ( "$sdir" == "backward" && "$key" == "N" ) ]]; then
        ni=$(( ni + 1 ))
      else
        ni=$(( ni - 1 ))
      fi
      (( ni > total )) && ni=1
      (( ni < 1 )) && ni=$total
      cmh_search_set "$ni" "$(( ${nh:-0} - ${no:-0} + ${ncy:-0} )),${ncx:-0}"
    else
      "${0%/*}/search-index.sh" "$pane"
    fi
    ;;
  r) tmux send-keys -t "$pane" -X refresh-from-pane ;;

  v|space)
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
    # helix 'x' (extend_line_below): select the current line, expand an
    # arbitrary active selection to full lines, and add the next line only when
    # the current selection is unchanged since the previous x. Existing
    # selections are adjusted in place so repeated x stays O(1).
    if [[ "$(tmux display -p -t "$pane" '#{selection_active}' 2>/dev/null || printf 0)" == "1" ]]; then
      sig="$(cmh_selection_signature)"
      if [[ -n "$sig" && "$(tmux show-option -pv -t "$pane" @cmh_x_sel 2>/dev/null || true)" == "$sig" ]]; then
        cmh_x_adjust_selection 1
      else
        cmh_x_adjust_selection 0
      fi
    else
      tmux send-keys -t "$pane" -X start-of-line
      tmux send-keys -t "$pane" -X begin-selection
      tmux send-keys -t "$pane" -X end-of-line
    fi
    tmux set-option -p -t "$pane" @cmh_x_sel "$(cmh_selection_signature)" >/dev/null 2>&1
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
  asterisk|hash)
    # send-keys does not expand formats, so resolve the word first. Use the
    # -text search commands: plain search-forward treats the word as regex.
    word="$(tmux display -p -t "$pane" '#{copy_cursor_word}' 2>/dev/null || true)"
    if [[ -n "$word" ]]; then
      if [[ "$key" == "asterisk" ]]; then
        cmh_search_begin "$word" 0 forward
        tmux send-keys -t "$pane" -X search-forward-text -- "$word"
      else
        cmh_search_begin "$word" 0 backward
        tmux send-keys -t "$pane" -X search-backward-text -- "$word"
      fi
      "${0%/*}/search-index.sh" "$pane"
    else
      cmh_search_set '' ''
    fi
    ;;

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
    mode_now="$(cmh_mode_get "$pane")"
    sel_active="$(tmux display-message -p -t "$pane" '#{selection_active}' 2>/dev/null || printf 0)"
    if [[ "$mode_now" == "extend" || "$sel_active" == "1" ]]; then
      # Exit selection/SEL mode, returning to normal (NOR) mode while
      # staying in tmux copy mode instead of cancelling the whole session.
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
