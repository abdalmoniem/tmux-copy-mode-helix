#!/usr/bin/env bash
# Unified Helix key dispatcher for tmux copy mode.
# keys.sh <key-token> <pane>
key="${1:-}"
pane="${2:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"

cmh_search_set() {
  tmux set-option -p -t "$pane" @cmh_search_index "${1:-}" \; \
       set-option -p -t "$pane" @cmh_search_pos "${2:-}" >/dev/null 2>&1
}

# Normal when @cmh_mode is unset or any value other than "extend"; the same
# test the native bindings use. tmux's search is a cursor motion, so with a
# selection already active it extends that selection to the match. Helix keeps
# normal-mode searches unselected, so collapse the old range first; extend-mode
# searches still grow it.
cmh_normal_cond='#{?#{@cmh_mode},#{!=:#{@cmh_mode},extend},1}'

# The indicator is drawn on the pane's top line, and cursor motions only
# repaint the lines they touch, so repaint after every key. toggle-position is
# CLEAR_NEVER (search marks survive) and toggling twice leaves visibility as
# it was. The vertical goal column only survives consecutive j/k moves.
cmh_keep_goal=0
cmh_goal_value=''
cmh_redraw() {
  # Fast vertical keys did the goal write and the repaint inside their own
  # two-call pipeline; running this again would clear the goal and repaint
  # twice.
  (( cmh_fast_done == 1 )) && return 0
  if [[ "$cmh_keep_goal" == "1" ]]; then
    tmux set-option -p -t "$pane" @cmh_goal_col "$cmh_goal_value" \; \
         send-keys -t "$pane" -X toggle-position \; \
         send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
  else
    tmux set-option -p -t "$pane" @cmh_goal_col '' \; \
         send-keys -t "$pane" -X toggle-position \; \
         send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
  fi
}
trap cmh_redraw EXIT
# Vertical motion keeps the cursor's column. tmux only records its goal column
# when the cursor is not at end-of-line, so from EOL it reuses a stale column
# and jumps to the start of the next line. Move with tmux, then put the cursor
# back on the remembered column (clamped to the target row). The goal survives
# consecutive j/k presses, so crossing a short line does not shrink it
# permanently; every other key clears it in cmh_redraw.
# Zero-width/format codepoints: bidi isolates (U+2066-2069), bidi controls
# (U+202A-202E), LRM/RLM (U+200E-200F), joiners and invisible maths
# (U+200B-200D, U+2060-2064), isolate end (U+206A-206F), variation selectors
# (U+FE00-FE0F), BOM (U+FEFF) and combining diacritics (U+0300-036F). tmux
# folds them into the previous cell: they occupy no cursor cell but still
# appear in #{copy_cursor_line}. Counting the raw string overruns the real
# row length and cursor-right then wraps the cursor down a row (an endless
# up/down bounce on lines with bidi isolates, e.g. apt output). The strip
# class is only used when the locale is multi-byte (${#sample} == 1); under
# a C locale it would delete bytes and mangle the string. After cleaning,
# every remaining character occupies at least one cell, so the count can
# only undershoot the row's real length, never overshoot.
cmh_nzw=$'\u200b\u200c\u200d\u200e\u200f\u202a\u202b\u202c\u202d\u202e\u2060\u2061\u2062\u2063\u2064\u2066\u2067\u2068\u2069\u206a\u206b\u206c\u206d\u206e\u206f\ufeff\ufe00\ufe01\ufe02\ufe03\ufe04\ufe05\ufe06\ufe07\ufe08\ufe09\ufe0a\ufe0b\ufe0c\ufe0d\ufe0e\ufe0f'$'\u0300\u0301\u0302\u0303\u0304\u0305\u0306\u0307\u0308\u0309\u030a\u030b\u030c\u030d\u030e\u030f\u0310\u0311\u0312\u0313\u0314\u0315\u0316\u0317\u0318\u0319\u031a\u031b\u031c\u031d\u031e\u031f\u0320\u0321\u0322\u0323\u0324\u0325\u0326\u0327\u0328\u0329\u032a\u032b\u032c\u032d\u032e\u032f\u0330\u0331\u0332\u0333\u0334\u0335\u0336\u0337\u0338\u0339\u033a\u033b\u033c\u033d\u033e\u033f\u0340\u0341\u0342\u0343\u0344\u0345\u0346\u0347\u0348\u0349\u034a\u034b\u034c\u034d\u034e\u034f\u0350\u0351\u0352\u0353\u0354\u0355\u0356\u0357\u0358\u0359\u035a\u035b\u035c\u035d\u035e\u035f\u0360\u0361\u0362\u0363\u0364\u0365\u0366\u0367\u0368\u0369\u036a\u036b\u036c\u036d\u036e\u036f'
# ${#sample} is 1 in a UTF-8 locale (char-aware) and 3 under C (byte counts),
# in which case the strip class would delete bytes and mangle the string.
cmh_zw_sample=$'\u2066'

# Cell length of a row string: drop zero-width codepoints, then count chars.
cmh_row_len() {
  local s="$1"
  if (( ${#cmh_zw_sample} == 1 )); then
    s="${s//[$cmh_nzw]/}"
  fi
  cmh_len="${#s}"
}


# ---- fast vertical path -----------------------------------------------------
# j/k/Up/Down are the keys users hold down. The classic path below costs a
# prelude read, the move and the exit trap: three to four tmux client round
# trips per keypress, which is slower than terminal key repeat, so held keys
# queue up and the cursor keeps drifting after release. This path does the
# same work in two calls:
#   call 1: everything tmux can decide on its own, branched with if-shell -F
#           (a format check -- no shell spawn): the pre-move state read fused
#           in, selection clearing, the move, and the indicator dance when the
#           landing row carries the indicator.
#   call 2: the column adjustment plus its verify read, the goal/x_sel/search
#           option writes and the indicator repaint -- work bash could only
#           know after call 1's reads.
# Returns 1 when the key must take the classic path (a prefix is pending, or
# tmux produced no pipeline output); cmh_fast_done tells the EXIT trap its
# work is already done.
cmh_fast_done=0
cmh_vertical_fast() {
  local dir="$1" out pline rest second pcx pcy goal_opt xsel sindex spos
  local goal col cur line tcy len vout
  local pfmt='P#{copy_cursor_x}|#{copy_cursor_y}|#{@cmh_goal_col}|#{@cmh_x_sel}|#{@cmh_search_index}|#{@cmh_search_pos}'
  local xfmt='X#{copy_cursor_x}|#{copy_cursor_y}|#{copy_cursor_line}'
  local yfmt='Y#{copy_cursor_line}'
  local qfmt='Q#{copy_cursor_x}|#{copy_cursor_y}|#{copy_cursor_line}'
  # tmux's command lexer treats a bare | as a pipe separator, so display
  # formats always need quoting; inside branch strings that are themselves
  # single-quoted, use double quotes so the levels cannot collide.
  local dance_branch="send-keys -t $pane -X toggle-position ; display-message -p -t $pane \"$xfmt\" ; send-keys -t $pane -X toggle-position ; display-message -p -t $pane \"$yfmt\""
  local plain_branch="display-message -p -t $pane \"$qfmt\""
  # e|!= is a NUMERIC comparator: with string operands it expands to empty,
  # which if-shell treats as false, so clear-selection would silently never
  # run (xjx: a normal-mode j must cancel the x line-selection). The native
  # #{!=:...} compares strings correctly; the ?-wrapper keeps it true when
  # @cmh_mode is unset.
  local mode_cond='#{?#{@cmh_mode},#{!=:#{@cmh_mode},extend},1}'
  local head_branch="display-message -p -t $pane '$pfmt' ; if-shell -t $pane -F '$mode_cond' 'send-keys -t $pane -X clear-selection' ; send-keys -t $pane -X cursor-$dir ; if-shell -t $pane -F '#{e|==:#{copy_cursor_y},0}' '$dance_branch' '$plain_branch'"

  out="$(tmux if-shell -t "$pane" -F '#{?#{@cmh_pending},0,1}' "$head_branch" '' 2>/dev/null)"
  [[ -z "$out" ]] && return 1

  pline="${out%%$'\n'*}"
  rest="${out#*$'\n'}"
  [[ "$rest" == "$out" ]] && rest=''
  IFS='|' read -r pcx pcy goal_opt xsel sindex spos <<< "${pline#P}"
  if [[ -z "$rest" || ( "$rest" != X* && "$rest" != Q* ) ]]; then
    return 1
  fi
  if [[ "$rest" == X* ]]; then
    second="${rest#*$'\n'}"
    IFS='|' read -r cur tcy line <<< "${rest#X}"
    if [[ "$second" == Y* ]]; then
      second="${second#Y}"
      cmh_row_len "$line"
      local a="$cmh_len"
      cmh_row_len "$second"
      (( cmh_len < a )) && line="$second"
    fi
    cmh_row_len "$line"
  else
    IFS='|' read -r cur tcy line <<< "${rest#Q}"
    cmh_row_len "$line"
  fi
  len="${cmh_len:-0}"
  tcy="${tcy:-$pcy}"
  cur="${cur:-0}"
  goal="${goal_opt:-$pcx}"
  col="$goal"
  (( col > len )) && col=$len

  # Call 2: column adjustment, then option writes; the toggles last so the
  # repaint shows the final column. The verify read catches a rights overrun
  # (wide-character step slop wraps the cursor down a row) and the corrective
  # re-toggles, so drift repaints with the restored row.
  local tail=(set-option -p -t "$pane" @cmh_goal_col "$goal")
  [[ -n "$xsel" ]] && tail+=( ';' set-option -p -t "$pane" @cmh_x_sel '' )
  [[ -n "$sindex$spos" ]] && tail+=( ';' set-option -p -t "$pane" @cmh_search_index '' ';' set-option -p -t "$pane" @cmh_search_pos '' )
  vout=''
  if (( cur > col )); then
    vout="$(tmux send-keys -t "$pane" -N "$(( cur - col ))" -X cursor-left ';' \
           display-message -p -t "$pane" 'V#{copy_cursor_x}|#{copy_cursor_y}' ';' \
           "${tail[@]}" ';' \
           send-keys -t "$pane" -X toggle-position ';' \
           send-keys -t "$pane" -X toggle-position 2>/dev/null)"
  elif (( cur < col )); then
    vout="$(tmux send-keys -t "$pane" -N "$(( col - cur ))" -X cursor-right ';' \
           display-message -p -t "$pane" 'V#{copy_cursor_x}|#{copy_cursor_y}' ';' \
           "${tail[@]}" ';' \
           send-keys -t "$pane" -X toggle-position ';' \
           send-keys -t "$pane" -X toggle-position 2>/dev/null)"
  else
    tmux "${tail[@]}" ';' \
         send-keys -t "$pane" -X toggle-position ';' \
         send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
  fi
  if [[ -n "$vout" ]]; then
    local vcx vcy
    IFS='|' read -r vcx vcy <<< "${vout#V}"
    vcy="${vcy:-$tcy}"
    if (( vcy > tcy )); then
      tmux send-keys -t "$pane" -N "$(( vcy - tcy ))" -X cursor-up ';' \
           send-keys -t "$pane" -X toggle-position ';' \
           send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
    elif (( vcy < tcy )); then
      tmux send-keys -t "$pane" -N "$(( tcy - vcy ))" -X cursor-down ';' \
           send-keys -t "$pane" -X toggle-position ';' \
           send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
    fi
  fi
  cmh_fast_done=1
  return 0
}

# ---- fused dispatcher paths ------------------------------------------------
# Run one already-built command list, then clear the vertical goal and toggle
# the indicator twice. State clears go at the front of the caller's list and
# the repaint is always last, so a command that fails cannot leave the
# indicator half-toggled. One client call, trap skipped via cmh_fast_done.
cmh_fused_run() {
  tmux "$@" \
    ';' set-option -p -t "$pane" @cmh_goal_col '' \
    ';' send-keys -t "$pane" -X toggle-position \
    ';' send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
  cmh_fast_done=1
}

# Start a fused pending-chord chain: clear the prefix and the transient state
# the classic prelude/trap would have cleared. The action is appended by the
# caller and cmh_fused_run finishes with the goal clear and the repaint.
cmh_state_head() {
  cmh_chain=( set-option -p -t "$pane" @cmh_pending ''
              ';' set-option -p -t "$pane" @cmh_x_sel ''
              ';' set-option -p -t "$pane" @cmh_search_index ''
              ';' set-option -p -t "$pane" @cmh_search_pos '' )
}

# Half page down/up: C-d/C-u with nothing pending, or u/d after z. All inputs
# (pending, mode, cursor column, pane height) come from the prelude read.
# Returns 1 for any other shape so the untouched classic path runs.
cmh_halfpage_fast() {
  local dir="$1" n c
  if [[ "$key" == "C-d" || "$key" == "C-u" ]]; then
    [[ -n "$pending" ]] && return 1
  else
    [[ "$pending" == "z" ]] || return 1
  fi
  n=$(( ${pane_height:-1} / 2 )); (( n < 1 )) && n=1
  c=( set-option -p -t "$pane" @cmh_pending ''
      ';' set-option -p -t "$pane" @cmh_x_sel ''
      ';' set-option -p -t "$pane" @cmh_search_index ''
      ';' set-option -p -t "$pane" @cmh_search_pos '' )
  [[ "$m" != "extend" ]] && c+=( ';' send-keys -t "$pane" -X clear-selection )
  (( cx > 0 )) && c+=( ';' send-keys -t "$pane" -X cursor-left )
  c+=( ';' send-keys -t "$pane" -X -N "$n" "cursor-$dir" )
  (( cx > 0 )) && c+=( ';' send-keys -t "$pane" -X cursor-right )
  cmh_fused_run "${c[@]}"
  return 0
}

# n/N: read the pre-search state, run the search and read the post-search
# counts in one client call. Formats expand as each queued command runs, so
# the P line sees the pre-move cursor and the Q line the post-move counts.
# Returns 1 only when nothing was executed (safe to take the classic path).
cmh_nav_fast() {
  local out pline q sindex spos sdir ph po py px
  local total partial nh no ncy ncx ni cur cheap fm bm
  # n always moves down and N always moves up. search-again follows the
  # search direction, search-reverse opposes it, so pick by direction.
  if [[ "$key" == "n" ]]; then fm=search-again; bm=search-reverse; else fm=search-reverse; bm=search-again; fi
  out="$(tmux set-option -p -t "$pane" @cmh_pending '' \
    ';' set-option -p -t "$pane" @cmh_x_sel '' \
    ';' set-option -p -t "$pane" @cmh_goal_col '' \
    ';' if-shell -t "$pane" -F "$cmh_normal_cond" "send-keys -t $pane -X clear-selection" \
    ';' display-message -p -t "$pane" "P#{@cmh_search_index}|#{@cmh_search_pos}|#{@cmh_search_dir}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}" \
    ';' if-shell -t "$pane" -F "#{==:#{@cmh_search_dir},forward}" "send-keys -t $pane -X $fm" "send-keys -t $pane -X $bm" \
    ';' display-message -p -t "$pane" "Q#{search_count}|#{search_count_partial}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}" \
    2>/dev/null)"
  [[ -z "$out" ]] && return 1
  pline="${out%%$'\n'*}"
  q="${out#*$'\n'}"
  if [[ "$pline" != P* ]]; then
    # Nonempty output but not our header: something in the chain executed.
    # Never take the classic path here, or the search could run twice.
    cmh_fused_run set-option -p -t "$pane" @cmh_search_index '' \
      ';' set-option -p -t "$pane" @cmh_search_pos ''
    return 0
  fi
  if [[ "$q" == "$pline" ]]; then
    # The search itself failed or returned no counts: mirror the classic
    # total=='' branch; never re-run the search from the fallback.
    cmh_fused_run set-option -p -t "$pane" @cmh_search_index '' \
      ';' set-option -p -t "$pane" @cmh_search_pos ''
    return 0
  fi
  IFS='|' read -r sindex spos sdir ph po py px <<< "${pline#P}"
  IFS='|' read -r total partial nh no ncy ncx <<< "${q#Q}"
  cur="$(( ${ph:-0} - ${po:-0} + ${py:-0} )),${px:-0}"
  cheap=0
  [[ "$sindex" =~ ^[0-9]+$ && "$spos" == "$cur" && -n "$sdir" && "${partial:-0}" != "1" ]] && cheap=1
  if [[ -z "${total:-}" ]]; then
    cmh_fused_run set-option -p -t "$pane" @cmh_search_index '' \
      ';' set-option -p -t "$pane" @cmh_search_pos ''
  elif (( cheap )); then
    ni="$sindex"
    # n moves down and N moves up regardless of the search direction. The
    # index follows that direction (forward: top-down, backward: bottom-up),
    # so its delta depends on both the key and the direction.
    if [[ "$key" == "n" ]]; then
      [[ "$sdir" == "forward" ]] && ni=$(( ni + 1 )) || ni=$(( ni - 1 ))
    else
      [[ "$sdir" == "forward" ]] && ni=$(( ni - 1 )) || ni=$(( ni + 1 ))
    fi
    (( ni > total )) && ni=1
    (( ni < 1 )) && ni=$total
    cmh_fused_run set-option -p -t "$pane" @cmh_search_index "$ni" \
      ';' set-option -p -t "$pane" @cmh_search_pos "$(( ${nh:-0} - ${no:-0} + ${ncy:-0} )),${ncx:-0}"
  else
    # Recount path: search-index.sh owns the index write and repaint.
    "${0%/*}/search-index.sh" "$pane"
    cmh_fast_done=1
  fi
  return 0
}

# * / #: the word has to be read first because its value feeds both the option
# writes and the search argument. The word is passed as one argv after --, so
# semicolons, quotes and leading dashes cannot be re-parsed.
cmh_star_fast() {
  local word dir c
  word="$(tmux display -p -t "$pane" '#{copy_cursor_word}' 2>/dev/null || true)"
  if [[ -z "$word" ]]; then
    cmh_fused_run set-option -p -t "$pane" @cmh_pending '' \
      ';' set-option -p -t "$pane" @cmh_x_sel '' \
      ';' set-option -p -t "$pane" @cmh_search_index '' \
      ';' set-option -p -t "$pane" @cmh_search_pos ''
    return 0
  fi
  [[ "$key" == "asterisk" ]] && dir=forward || dir=backward
  c=( set-option -p -t "$pane" @cmh_pending ''
      ';' set-option -p -t "$pane" @cmh_x_sel ''
      ';' set-option -p -t "$pane" @cmh_search_pattern "$word"
      ';' set-option -p -t "$pane" @cmh_search_regex 0
      ';' set-option -p -t "$pane" @cmh_search_dir "$dir"
      ';' set-option -p -t "$pane" @cmh_search_index ''
      ';' set-option -p -t "$pane" @cmh_search_pos ''
      ';' if-shell -t "$pane" -F "$cmh_normal_cond" "send-keys -t $pane -X clear-selection" \
      ';' send-keys -t "$pane" -X "search-$dir-text" -- "$word"
      ';' set-option -p -t "$pane" @cmh_goal_col '' )
  tmux "${c[@]}" >/dev/null 2>&1
  # search-index.sh always writes index/pos and repaints on every exit path.
  "${0%/*}/search-index.sh" "$pane"
  cmh_fast_done=1
  return 0
}

# x/X/V: fold the four classic reads into one display, reproduce
# cmh_x_adjust_selection's arithmetic, send every selection command as one
# chain, and write the new signature with set-option -F (expanded after the
# moves execute). Returns 1 before any side effect if the read fails.
cmh_x_fast() {
  local out active xsig xsx xsy xex xey xcx xcy xhsize xoy
  local cur lx ly hx hy ctl extend xsig_now c
  out="$(tmux display -p -t "$pane" \
    '#{selection_active}|#{@cmh_x_sel}|#{selection_start_x}|#{selection_start_y}|#{selection_end_x}|#{selection_end_y}|#{copy_cursor_x}|#{copy_cursor_y}|#{history_size}|#{scroll_position}' \
    2>/dev/null)"
  [[ -z "$out" ]] && return 1
  IFS='|' read -r active xsig xsx xsy xex xey xcx xcy xhsize xoy <<< "$out"
  cur=$(( ${xhsize:-0} - ${xoy:-0} + ${xcy:-0} ))

  if (( ${xsy:-0} < ${xey:-0} || (${xsy:-0} == ${xey:-0} && ${xsx:-0} <= ${xex:-0}) )); then
    lx=$xsx; ly=$xsy; hx=$xex; hy=$xey
  else
    lx=$xex; ly=$xey; hx=$xsx; hy=$xsy
  fi
  if [[ "$xcx,$cur" == "$lx,$ly" && "$xcx,$cur" != "$hx,$hy" ]]; then
    ctl=low
  elif [[ "$xcx,$cur" == "$hx,$hy" ]]; then
    ctl=high
  elif (( cur == ly )); then
    ctl=low
  else
    ctl=high
  fi

  c=( set-option -p -t "$pane" @cmh_pending ''
      ';' set-option -p -t "$pane" @cmh_x_sel ''
      ';' set-option -p -t "$pane" @cmh_search_index ''
      ';' set-option -p -t "$pane" @cmh_search_pos '' )
  if [[ "$active" == "1" ]]; then
    extend=0
    xsig_now="${xsx},${xsy},${xex},${xey}"
    [[ -n "$xsig" && "$xsig" == "$xsig_now" ]] && extend=1
    if [[ "$extend" != "1" && "$lx" != "0" ]]; then
      [[ "$ctl" != "low" ]] && c+=( ';' send-keys -t "$pane" -X other-end )
      c+=( ';' send-keys -t "$pane" -X start-of-line
           ';' send-keys -t "$pane" -X other-end )
      ctl=high
    fi
    [[ "$ctl" != "high" ]] && c+=( ';' send-keys -t "$pane" -X other-end )
    if [[ "$extend" == "1" ]]; then
      c+=( ';' send-keys -t "$pane" -X end-of-line
           ';' send-keys -t "$pane" -X cursor-down )
    fi
    c+=( ';' send-keys -t "$pane" -X end-of-line )
  else
    c+=( ';' send-keys -t "$pane" -X start-of-line
         ';' send-keys -t "$pane" -X begin-selection
         ';' send-keys -t "$pane" -X end-of-line )
  fi
  c+=( ';' set-option -p -F -t "$pane" @cmh_x_sel \
       '#{selection_start_x},#{selection_start_y},#{selection_end_x},#{selection_end_y}' )
  cmh_fused_run "${c[@]}"
  return 0
}

case "$key" in
  j|Down) cmh_vertical_fast down ;;
  k|Up)   cmh_vertical_fast up ;;
  n|N) cmh_nav_fast ;;
  asterisk|hash) cmh_star_fast ;;
  x|X|V) cmh_x_fast ;;
esac
(( cmh_fast_done == 1 )) && exit 0

# Read pending/mode/x/search state, the vertical goal column and the cursor in
# one tmux call. '|' preserves empty fields.
IFS='|' read -r pending m xsel sindex spos sdir goal_opt hsize oy cy cx pane_height < <(tmux display -p -t "$pane" \
  '#{@cmh_pending}|#{@cmh_mode}|#{@cmh_x_sel}|#{@cmh_search_index}|#{@cmh_search_pos}|#{@cmh_search_dir}|#{@cmh_goal_col}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}|#{pane_height}' \
  2>/dev/null)
m="${m:-normal}"
hsize="${hsize:-0}"; oy="${oy:-0}"; cy="${cy:-0}"; cx="${cx:-0}"; pane_height="${pane_height:-1}"

# Fused half page: the prelude already read mode/pending/column/height, so a
# claim costs exactly one more call. C-d/C-u only with no prefix; u/d only
# after z. Anything else falls through to the classic handler.
case "$key" in
  C-d) [[ -z "$pending" ]] && cmh_halfpage_fast down ;;
  C-u) [[ -z "$pending" ]] && cmh_halfpage_fast up ;;
  u)   [[ "$pending" == "z" ]] && cmh_halfpage_fast up ;;
  d)   [[ "$pending" == "z" ]] && cmh_halfpage_fast down ;;
esac
(( cmh_fast_done == 1 )) && exit 0

# Fused pending chords do their own state clears inside the action chain;
# running the generic clears first would add round trips to the keys being
# fused. Only recognized, fully-fused combinations are gated here.
cmh_fused_pending=0
if [[ -n "$pending" ]]; then
  case "${pending}-${key}" in
    g-g|g-e|g-h|g-l|g-s|g-t|g-c|g-b|g-j|g-k|z-z|z-c|z-t|z-b|z-j|z-k|m-m)
      cmh_fused_pending=1 ;;
  esac
fi
if (( cmh_fused_pending == 0 )); then
  # Only x/X/V and keys that leave the selection untouched may reuse the
  # x-owned selection state; everything else starts a fresh x range.
  case "$key" in
    x|X|V|o|v|space) ;;
    *) [[ -n "$xsel" ]] && tmux set-option -p -t "$pane" @cmh_x_sel '' >/dev/null 2>&1 ;;
  esac

  # @cmh_search_index names the match under the cursor; any cursor motion
  # leaves it, so drop the index (the results section disappears). Mode
  # toggles (v/space) do not move, so they keep it.
  case "$key" in
    n|N|asterisk|hash|v|space) ;;
    *) [[ -n "$sindex$spos" ]] && cmh_search_set '' '' ;;
  esac
fi

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

cmh_cursor_vertical() {
  local dir="$1" goal col cur line out top=0 first second tcy len vout
  local cmd=(tmux send-keys -t "$pane")

  goal="${goal_opt:-$cx}"
  col="$goal"

  if [[ "$m" == "extend" ]]; then
    cmd+=(-X "cursor-$dir")
  else
    cmd+=(-X clear-selection ';' send-keys -t "$pane" -X "cursor-$dir")
  fi

  # The position indicator replaces the top visible row, so toggle it while
  # reading that row's text and keep whichever reading is unpolluted (the
  # indicator may already have been hidden). toggle-position keeps the marks.
  if [[ "$dir" == "up" ]] && (( cy <= 1 )); then
    top=1
    cmd+=(';' send-keys -t "$pane" -X toggle-position \
          ';' display-message -p -t "$pane" 'X#{copy_cursor_x}|#{copy_cursor_y}|#{copy_cursor_line}' \
          ';' send-keys -t "$pane" -X toggle-position \
          ';' display-message -p -t "$pane" 'Y#{copy_cursor_line}')
  else
    cmd+=(';' display-message -p -t "$pane" '#{copy_cursor_x}|#{copy_cursor_y}|#{copy_cursor_line}')
  fi
  out="$("${cmd[@]}" 2>/dev/null)"

  if (( top )); then
    first="${out%%$'\n'*}"
    second="${out#*$'\n'}"
    IFS='|' read -r cur tcy line <<< "${first#X}"
    second="${second#Y}"
    cmh_row_len "$line"
    local a="$cmh_len"
    cmh_row_len "$second"
    (( cmh_len < a )) && line="$second"
    cmh_row_len "$line"
  else
    IFS='|' read -r cur tcy line <<< "$out"
    cmh_row_len "$line"
  fi
  len="${cmh_len:-0}"
  tcy="${tcy:-$cy}"
  cur="${cur:-0}"
  (( col > len )) && col=$len

  # Column adjustment plus a position read. The step counts are in cursor
  # steps, so on rows with wide characters the rights can still overrun the
  # row end and wrap down; catch the drift and pull the cursor straight back
  # with tmux's own clamping (bounded: at most one corrective, no loop).
  if (( cur > col )); then
    vout="$(tmux send-keys -t "$pane" -N "$(( cur - col ))" -X cursor-left \
            ';' display-message -p -t "$pane" '#{copy_cursor_x}|#{copy_cursor_y}' 2>/dev/null)"
  elif (( cur < col )); then
    vout="$(tmux send-keys -t "$pane" -N "$(( col - cur ))" -X cursor-right \
            ';' display-message -p -t "$pane" '#{copy_cursor_x}|#{copy_cursor_y}' 2>/dev/null)"
  fi
  if [[ -n "${vout:-}" ]]; then
    local vcy vcx
    IFS='|' read -r vcx vcy <<< "$vout"
    vcy="${vcy:-$tcy}"
    if (( vcy > tcy )); then
      tmux send-keys -t "$pane" -N "$(( vcy - tcy ))" -X cursor-up >/dev/null 2>&1
    elif (( vcy < tcy )); then
      tmux send-keys -t "$pane" -N "$(( tcy - vcy ))" -X cursor-down >/dev/null 2>&1
    fi
  fi
  cmh_keep_goal=1
  cmh_goal_value="$goal"
}

clear_pending() { tmux set-option -p -t "$pane" @cmh_pending '' >/dev/null 2>&1; }
set_pending() { tmux set-option -p -t "$pane" @cmh_pending "${1:-}" >/dev/null 2>&1; }
begin_normal() {
  if [[ "$m" != "extend" ]]; then
    tmux send-keys -t "$pane" -X begin-selection
  fi
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
# Fused chords run as one client call: state clears, the selection branch, the
# motion and the repaint. cmh_fused_run sets cmh_fast_done so the EXIT trap
# does not repaint a second time.
if [[ -n "$pending" ]]; then
  case "${pending}-${key}" in
    g-g|g-e|g-h|g-l|g-s|g-j|g-k)
      cmh_state_head
      [[ "$m" != "extend" ]] && cmh_chain+=( ';' send-keys -t "$pane" -X clear-selection )
      case "$key" in
        g) cmh_motion=history-top ;;
        e) cmh_motion=history-bottom ;;
        h) cmh_motion=start-of-line ;;
        l) cmh_motion=end-of-line ;;
        s) cmh_motion=back-to-indentation ;;
        j) cmh_motion=cursor-down ;;
        k) cmh_motion=cursor-up ;;
      esac
      cmh_chain+=( ';' send-keys -t "$pane" -X "$cmh_motion" )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    g-t|g-c|g-b)
      cmh_state_head
      [[ "$m" != "extend" ]] && cmh_chain+=( ';' send-keys -t "$pane" -X clear-selection )
      case "$key" in
        t) cmh_target=top-line ;;
        c) cmh_target=middle-line ;;
        b) cmh_target=bottom-line ;;
      esac
      cmh_chain+=( ';' send-keys -t "$pane" -X "$cmh_target" )
      (( cx > 0 )) && cmh_chain+=( ';' send-keys -t "$pane" -X -N "$cx" cursor-right )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-z|z-c)
      cmh_state_head
      cmh_chain+=( ';' send-keys -t "$pane" -X scroll-middle )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-t)
      cmh_state_head
      cmh_chain+=( ';' send-keys -t "$pane" -X scroll-top )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-b)
      cmh_state_head
      cmh_chain+=( ';' send-keys -t "$pane" -X scroll-bottom )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-j)
      cmh_state_head
      cmh_chain+=( ';' send-keys -t "$pane" -X scroll-down )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-k)
      cmh_state_head
      cmh_chain+=( ';' send-keys -t "$pane" -X scroll-up )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    z-u)
      # Unreachable while the fused half-page path claims z u; kept as the
      # classic fallback.
      clear_pending; cmh_halfpage up; exit 0 ;;
    z-d)
      clear_pending; cmh_halfpage down; exit 0 ;;
    m-m)
      # begin-selection only in normal mode. $m defaults to normal when the
      # option is unset, matching cmh_mode_get.
      cmh_state_head
      [[ "$m" != "extend" ]] && cmh_chain+=( ';' send-keys -t "$pane" -X begin-selection )
      cmh_chain+=( ';' send-keys -t "$pane" -X next-matching-bracket )
      cmh_fused_run "${cmh_chain[@]}"
      exit 0 ;;
    g-w)
      clear_pending; cmh_alert "$pane" 'goto-word needs tree-sitter'; exit 0 ;;
    prev-p)
      clear_pending; key=goto motion previous-paragraph; exit 0 ;;
    next-p)
      clear_pending; key=goto motion next-paragraph; exit 0 ;;
  esac
  # Unknown combination: clear pending exactly once and fall through. The
  # shell copy must die with it so the tail below does not issue a second
  # clear (old keys.sh:470 + :664).
  clear_pending
  pending=''
fi

# ---- normal key handling ---------------------------------------------------
case "$key" in
  # second keys for g/z/[/] prefixes; handled above when a prefix is pending
  c|s|u|d|p) ;;
  h|Left) motion cursor-left ;;
  j|Down) cmh_cursor_vertical down ;;
  k|Up) cmh_cursor_vertical up ;;
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
    [[ "$sindex" =~ ^[0-9]+$ && "$spos" == "$cur" && -n "$sdir" && "${partial:-0}" != "1" ]] && cheap=1
    if [[ "$m" != "extend" ]]; then
      tmux send-keys -t "$pane" -X clear-selection
    fi
    # n always moves down and N always moves up. search-again follows the
    # search direction and search-reverse opposes it; pick the one that
    # travels the requested way.
    if [[ "$key" == "n" ]]; then
      [[ "$sdir" == "forward" ]] && tmux send-keys -t "$pane" -X search-again || tmux send-keys -t "$pane" -X search-reverse
    else
      [[ "$sdir" == "forward" ]] && tmux send-keys -t "$pane" -X search-reverse || tmux send-keys -t "$pane" -X search-again
    fi
    IFS='|' read -r total partial nh no ncy ncx < <(tmux display -p -t "$pane" \
      '#{search_count}|#{search_count_partial}|#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}' \
      2>/dev/null)
    if [[ -z "${total:-}" ]]; then
      cmh_search_set '' ''
    elif (( cheap )); then
      ni="$sindex"
      if [[ "$key" == "n" ]]; then
        [[ "$sdir" == "forward" ]] && ni=$(( ni + 1 )) || ni=$(( ni - 1 ))
      else
        [[ "$sdir" == "forward" ]] && ni=$(( ni - 1 )) || ni=$(( ni + 1 ))
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
    source "${0%/*}/common.sh"
    clip="$(cmh_clip_or_die "$pane")" || exit 0
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel -C "$clip"
    tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
    ;;
  Y)
    source "${0%/*}/common.sh"
    tmux send-keys -t "$pane" -X start-of-line
    tmux send-keys -t "$pane" -X begin-selection
    tmux send-keys -t "$pane" -X end-of-line
    clip="$(cmh_clip_or_die "$pane")" || exit 0
    tmux send-keys -t "$pane" -X copy-pipe-and-cancel -C "$clip"
    tmux set-option -p -t "$pane" @cmh_mode normal >/dev/null 2>&1
    ;;
  asterisk|hash)
    # send-keys does not expand formats, so resolve the word first. Use the
    # -text search commands: plain search-forward treats the word as regex.
    word="$(tmux display -p -t "$pane" '#{copy_cursor_word}' 2>/dev/null || true)"
    if [[ -n "$word" ]]; then
      if [[ "$key" == "asterisk" ]]; then
        cmh_search_begin "$word" 0 forward
        [[ "$m" != "extend" ]] && tmux send-keys -t "$pane" -X clear-selection
        tmux send-keys -t "$pane" -X search-forward-text -- "$word"
      else
        cmh_search_begin "$word" 0 backward
        [[ "$m" != "extend" ]] && tmux send-keys -t "$pane" -X clear-selection
        tmux send-keys -t "$pane" -X search-backward-text -- "$word"
      fi
      "${0%/*}/search-index.sh" "$pane"
    else
      cmh_search_set '' ''
    fi
    ;;

  # begin a minor mode / prefix
  g) set_pending "g" ;;
  z) set_pending "z" ;;
  m) set_pending "m" ;;
  lbracket) set_pending "prev" ;;
  rbracket) set_pending "next" ;;

  # prompt-based commands
  f)
    tmux command-prompt -1 -p "(find)" "set-option -p @cmh_find_char \"%%%\" ; run-shell -b '${0%/*}/find-char.sh jump-forward #{pane_id}'" ;;
  t)
    tmux command-prompt -1 -p "(till)" "set-option -p @cmh_find_char \"%%%\" ; run-shell -b '${0%/*}/find-char.sh jump-to-forward #{pane_id}'" ;;
  F)
    tmux command-prompt -1 -p "(find back)" "set-option -p @cmh_find_char \"%%%\" ; run-shell -b '${0%/*}/find-char.sh jump-backward #{pane_id}'" ;;
  T)
    tmux command-prompt -1 -p "(till back)" "set-option -p @cmh_find_char \"%%%\" ; run-shell -b '${0%/*}/find-char.sh jump-to-backward #{pane_id}'" ;;
  slash)
    # The pattern goes through a pane option, not through the run-shell
    # command line. command-prompt's %% interpolation loses regex backslashes
    # (e.g. \.sh became .sh), so store the response with %%% (which escapes
    # quotes) and let search.sh read the option; the shell never parses it.
    tmux command-prompt -T search -p "(search down)" "set-option -p @cmh_search_input \"%%%\" ; run-shell -b '${0%/*}/search.sh forward #{pane_id}'" ;;
  question)
    tmux command-prompt -T search -p "(search up)" "set-option -p @cmh_search_input \"%%%\" ; run-shell -b '${0%/*}/search.sh backward #{pane_id}'" ;;
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
    cmh_alert "$pane" "unbound key '$key'" ;;
esac
# clear pending if a normal command ran (prefix keys set it above); skip the
# client call when nothing is pending -- held keys pay for every round trip.
case "$key" in g|z|m|lbracket|rbracket) ;; *) [[ -z "$pending" ]] || clear_pending ;; esac
