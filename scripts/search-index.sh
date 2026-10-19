#!/usr/bin/env bash
# search-index.sh <pane>
#
# Recompute @cmh_search_index (the 1-based number of the match under the
# copy-mode cursor) and @cmh_search_pos ("line,col" where it was counted).
# tmux reports only the total (search_count) before search_count_current was
# added, so count the matches in the buffer up to the cursor ourselves using
# the pattern recorded by the search entry points.
#
# Matching mirrors copy mode: non-overlapping matches in buffer order, and
# smart case (an all-lowercase pattern matches case-insensitively). Pure
# $1 = pane option lookup.
pane="${1:-}"
[ -z "$pane" ] && exit 0

cmh_opt() { tmux show-option -pv -t "$pane" "$1" 2>/dev/null || true; }

cmh_clear() {
  tmux set-option -p -t "$pane" @cmh_search_index '' \; \
       set-option -p -t "$pane" @cmh_search_pos '' >/dev/null 2>&1
}

pat="$(cmh_opt @cmh_search_pattern)"
[ -z "$pat" ] && { cmh_clear; exit 0; }
regex="$(cmh_opt @cmh_search_regex)"

IFS='|' read -r hsize oy cy cx total partial < <(tmux display -p -t "$pane" \
  '#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}|#{search_count}|#{search_count_partial}' \
  2>/dev/null)
hsize="${hsize:-0}"; oy="${oy:-0}"; cy="${cy:-0}"; cx="${cx:-0}"
# No marks: nothing to be a current result of.
[ -z "${total:-}" ] && { cmh_clear; exit 0; }

line=$(( hsize - oy + cy ))
# capture-pane line numbers are relative to history_size: line v is the
# absolute grid line hsize + v. Include lines 0..line, i.e. up to the cursor.
content="$(tmux capture-pane -p -t "$pane" -S - -E "$(( cy - oy ))" 2>/dev/null || true)"
[ -z "$content" ] && { cmh_clear; exit 0; }

index="$(printf '%s\n' "$content" | \
  CMH_PAT="$pat" CMH_REGEX="$regex" CMH_LINE="$line" CMH_COL="$cx" \
  awk '
  BEGIN {
    pat = ENVIRON["CMH_PAT"]
    re = (ENVIRON["CMH_REGEX"] == "1")
    cur = ENVIRON["CMH_LINE"] + 0
    col = ENVIRON["CMH_COL"] + 0
    ci = (pat == tolower(pat))
    plen = length(pat)
    if (re) rpat = ci ? tolower(pat) : pat
    else lpat = ci ? tolower(pat) : pat
    # tmux passes REG_NOTBOL when it continues a line, so a leading ^ only
    # anchors at the start of the line.
    bol = (substr(pat, 1, 1) == "^")
    before = 0
    res = ""
  }
  function hit(n, p) {
    if (n < cur) { before++; return }
    if (n > cur) return
    if (p < col) { before++; return }
    if (p == col) res = before + 1
  }
  {
    n = NR - 1
    if (n > cur) exit
    line = ci ? tolower($0) : $0
    if (!re) {
      rest = line
      base = 0
      while (plen > 0) {
        p = index(rest, lpat)
        if (p == 0) break
        hit(n, base + p - 1)
        if (res != "") exit
        rest = substr(rest, p + plen)
        base += p + plen - 1
      }
    } else {
      rest = line
      base = 0
      while (length(rest) > 0) {
        if (bol && base > 0) break
        if (!match(rest, rpat)) break
        if (RLENGTH == 0) { rest = substr(rest, 2); base += 1; continue }
        hit(n, base + RSTART - 1)
        if (res != "") exit
        adv = RSTART + RLENGTH - 1
        rest = substr(rest, adv + 1)
        base += adv
      }
    }
  }
  END { print res }
  ' 2>/dev/null || true)"

if [[ -n "$index" ]]; then
  if [[ "${partial:-0}" != "1" && "$index" -gt "$total" ]]; then
    index="$total"
  fi
  tmux set-option -p -t "$pane" @cmh_search_index "$index" \; \
       set-option -p -t "$pane" @cmh_search_pos "$line,$cx" >/dev/null 2>&1
else
  cmh_clear
fi
