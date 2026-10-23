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

# Updating a pane option does not repaint copy mode; toggle-position twice
# forces a full redraw while leaving its visibility (and the search marks)
# unchanged.
cmh_set() {
  tmux set-option -p -t "$pane" @cmh_search_index "${1:-}" \; \
       set-option -p -t "$pane" @cmh_search_pos "${2:-}" \; \
       send-keys -t "$pane" -X toggle-position \; \
       send-keys -t "$pane" -X toggle-position >/dev/null 2>&1
}

cmh_clear() { cmh_set '' ''; }

# One client call for the whole read: the option values, cursor geometry and
# match counts, then the buffer text. Two option lookups plus a display and a
# capture used to cost four client forks, which is longer than the terminal
# repeat interval; commands in one list execute in order, so the display line
# is the first line of the output and the capture follows it. -E stops the
# capture at the cursor row: capturing the whole history made every recount
# slower than the terminal repeat rate on long scrollbacks.
out="$(tmux display -p -t "$pane" \
  '#{history_size}|#{scroll_position}|#{copy_cursor_y}|#{copy_cursor_x}|#{search_count}|#{search_count_partial}|#{@cmh_search_regex}|#{@cmh_search_dir}|#{@cmh_search_pattern}' \
  ';' capture-pane -p -t "$pane" -S - -E '#{e|-:#{copy_cursor_y},#{scroll_position}}' 2>/dev/null || true)"
header="${out%%$'\n'*}"
content="${out#*$'\n'}"
[[ "$content" == "$out" ]] && content=''
IFS='|' read -r hsize oy cy cx total partial regex dir pat <<< "$header"
pat="${pat:-}"
[ -z "$pat" ] && { cmh_clear; exit 0; }
hsize="${hsize:-0}"; oy="${oy:-0}"; cy="${cy:-0}"; cx="${cx:-0}"
# No marks: nothing to be a current result of.
[ -z "${total:-}" ] && { cmh_clear; exit 0; }
[ -z "$content" ] && { cmh_clear; exit 0; }

line=$(( hsize - oy + cy ))
# capture-pane line 0 is the first grid line of the history, so line
# hsize - scroll + cursor_y is the cursor's row. The capture above ends on
# that row, and awk stops there as well.

index="$(printf '%s\n' "$content" | \
  LC_ALL=C CMH_PAT="$pat" CMH_REGEX="$regex" CMH_LINE="$line" CMH_COL="$cx" \
  awk '
  BEGIN {
    for (i = 0; i < 256; i++) ORD[sprintf("%c", i)] = i
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
  # cell width of a UTF-8 string. tmux positions the cursor in cells, while
  # mawk (the default awk on Debian) counts bytes; without this conversion a
  # match after any non-ASCII character looked like it was to the right of the
  # cursor, the index was cleared, and the indicator fell back to the total.
  # Control and combining codepoints take no cells, East Asian wide and most
  # emoji take two, and everything else takes one.
  function cw(s,   i, n, b, cp, w) {
    n = length(s); i = 1; w = 0
    while (i <= n) {
      b = ORD[substr(s, i, 1)]
      if (b < 128) { cp = b; i += 1 }
      else if (b >= 194 && b <= 223) {
        cp = (b - 192) * 64 + ORD[substr(s, i + 1, 1)] - 128
        i += 2
      } else if (b >= 224 && b <= 239) {
        cp = (b - 224) * 4096 + (ORD[substr(s, i + 1, 1)] - 128) * 64 + ORD[substr(s, i + 2, 1)] - 128
        i += 3
      } else if (b >= 240 && b <= 244) {
        cp = (b - 240) * 262144 + (ORD[substr(s, i + 1, 1)] - 128) * 4096 + (ORD[substr(s, i + 2, 1)] - 128) * 64 + ORD[substr(s, i + 3, 1)] - 128
        i += 4
      } else { cp = b; i += 1 }
      if (cp < 32 || (cp >= 127 && cp < 160)) continue
      if ((cp >= 768 && cp <= 879) || (cp >= 1155 && cp <= 1161) ||
          (cp >= 1425 && cp <= 1469) || cp == 1471 ||
          (cp >= 1473 && cp <= 1474) || (cp >= 1476 && cp <= 1477) ||
          cp == 1479 || (cp >= 1552 && cp <= 1562) ||
          (cp >= 1611 && cp <= 1631) || cp == 1648 ||
          (cp >= 1750 && cp <= 1756) || (cp >= 1759 && cp <= 1764) ||
          (cp >= 1767 && cp <= 1768) || (cp >= 1770 && cp <= 1773) ||
          cp == 1809 || (cp >= 1840 && cp <= 1866) ||
          (cp >= 1958 && cp <= 1968) || (cp >= 2027 && cp <= 2035) ||
          (cp >= 2070 && cp <= 2093) || (cp >= 2137 && cp <= 2139) ||
          (cp >= 2200 && cp <= 2207) || (cp >= 2250 && cp <= 2306) ||
          (cp == 2362 || cp == 2364) || (cp >= 2369 && cp <= 2376) ||
          cp == 2381 || (cp >= 2385 && cp <= 2391) ||
          (cp >= 2402 && cp <= 2403) || cp == 2433 || cp == 2492 ||
          (cp >= 2497 && cp <= 2500) || cp == 2509 ||
          (cp >= 2530 && cp <= 2531) || (cp >= 2561 && cp <= 2562) ||
          cp == 2620 || (cp >= 2625 && cp <= 2626) ||
          (cp >= 2631 && cp <= 2632) || (cp >= 2635 && cp <= 2637) ||
          cp == 2641 || (cp >= 2672 && cp <= 2673) || cp == 2677 ||
          (cp >= 2689 && cp <= 2690) || cp == 2748 ||
          (cp >= 2753 && cp <= 2757) || (cp >= 2759 && cp <= 2760) ||
          cp == 2765 || (cp >= 2786 && cp <= 2787) || cp == 2817 ||
          cp == 2876 || cp == 2879 || (cp >= 2881 && cp <= 2884) ||
          cp == 2893 || (cp >= 2901 && cp <= 2902) ||
          (cp >= 2914 && cp <= 2915) || cp == 2946 || cp == 3008 ||
          cp == 3021 || cp == 3072 || cp == 3076 || cp == 3132 ||
          (cp >= 3134 && cp <= 3136) || (cp >= 3142 && cp <= 3144) ||
          (cp >= 3146 && cp <= 3149) || (cp >= 3157 && cp <= 3158) ||
          (cp >= 3170 && cp <= 3171) || cp == 3201 || cp == 3260 ||
          cp == 3263 || cp == 3270 || cp == 3272 ||
          (cp >= 3274 && cp <= 3277) || (cp >= 3285 && cp <= 3286) ||
          (cp >= 3298 && cp <= 3299) || (cp >= 3328 && cp <= 3329) ||
          (cp >= 3387 && cp <= 3388) || (cp >= 3393 && cp <= 3396) ||
          cp == 3405 || (cp >= 3426 && cp <= 3427) || cp == 3457 ||
          cp == 3530 || (cp >= 3538 && cp <= 3540) || cp == 3542 ||
          cp == 3633 || (cp >= 3636 && cp <= 3642) ||
          (cp >= 3655 && cp <= 3662) || cp == 3761 ||
          (cp >= 3764 && cp <= 3772) || (cp >= 3784 && cp <= 3790) ||
          (cp >= 3864 && cp <= 3865) || cp == 3893 || cp == 3895 ||
          cp == 3897 || (cp >= 3953 && cp <= 3966) ||
          (cp >= 3968 && cp <= 3972) || (cp >= 3974 && cp <= 3975) ||
          (cp >= 3981 && cp <= 3991) || (cp >= 3993 && cp <= 4028) ||
          cp == 4038 || (cp >= 4141 && cp <= 4144) ||
          (cp >= 4146 && cp <= 4151) || (cp >= 4153 && cp <= 4154) ||
          (cp >= 4157 && cp <= 4158) || (cp >= 4184 && cp <= 4185) ||
          (cp >= 4190 && cp <= 4192) || (cp >= 4209 && cp <= 4212) ||
          cp == 4226 || (cp >= 4229 && cp <= 4230) || cp == 4237 ||
          cp == 4253 || (cp >= 4448 && cp <= 4607) ||
          (cp >= 4957 && cp <= 4959) || (cp >= 5906 && cp <= 5908) ||
          (cp >= 5938 && cp <= 5939) || (cp >= 5970 && cp <= 5971) ||
          (cp >= 6002 && cp <= 6003) || (cp >= 6068 && cp <= 6069) ||
          (cp >= 6071 && cp <= 6077) || cp == 6086 ||
          (cp >= 6089 && cp <= 6099) || cp == 6109 ||
          (cp >= 6155 && cp <= 6159) || (cp >= 6277 && cp <= 6278) ||
          cp == 6313 || (cp >= 6432 && cp <= 6434) ||
          (cp >= 6439 && cp <= 6440) || cp == 6450 ||
          (cp >= 6457 && cp <= 6459) || (cp >= 6679 && cp <= 6680) ||
          cp == 6683 || cp == 6742 || (cp >= 6744 && cp <= 6750) ||
          cp == 6752 || cp == 6754 || (cp >= 6757 && cp <= 6764) ||
          (cp >= 6771 && cp <= 6780) || cp == 6783 ||
          (cp >= 6832 && cp <= 6862) || (cp >= 6912 && cp <= 6915) ||
          cp == 6964 || (cp >= 6966 && cp <= 6970) || cp == 6972 ||
          cp == 6978 || (cp >= 7019 && cp <= 7027) ||
          (cp >= 7040 && cp <= 7041) || (cp >= 7074 && cp <= 7077) ||
          (cp >= 7080 && cp <= 7081) || (cp >= 7083 && cp <= 7085) ||
          cp == 7142 || (cp >= 7144 && cp <= 7145) || cp == 7149 ||
          (cp >= 7151 && cp <= 7153) || (cp >= 7212 && cp <= 7219) ||
          (cp >= 7222 && cp <= 7223) || (cp >= 7376 && cp <= 7378) ||
          (cp >= 7380 && cp <= 7392) || (cp >= 7394 && cp <= 7400) ||
          cp == 7405 || cp == 7412 || (cp >= 7416 && cp <= 7417) ||
          (cp >= 7616 && cp <= 7679) || (cp >= 8203 && cp <= 8207) ||
          (cp >= 8234 && cp <= 8238) || (cp >= 8288 && cp <= 8292) ||
          (cp >= 8294 && cp <= 8303) || (cp >= 8400 && cp <= 8432) ||
          (cp >= 11503 && cp <= 11505) || cp == 11647 ||
          (cp >= 11744 && cp <= 11775) || (cp >= 12330 && cp <= 12333) ||
          (cp >= 12441 && cp <= 12442) || (cp >= 42607 && cp <= 42610) ||
          (cp >= 42612 && cp <= 42621) || (cp >= 42654 && cp <= 42655) ||
          (cp >= 42736 && cp <= 42737) || cp == 43010 || cp == 43014 ||
          cp == 43019 || (cp >= 43045 && cp <= 43046) || cp == 43052 ||
          (cp >= 43204 && cp <= 43205) || (cp >= 43232 && cp <= 43249) ||
          (cp >= 43302 && cp <= 43309) || (cp >= 43335 && cp <= 43345) ||
          (cp >= 43392 && cp <= 43394) || cp == 43443 ||
          (cp >= 43446 && cp <= 43449) || (cp >= 43452 && cp <= 43453) ||
          cp == 43493 || (cp >= 43561 && cp <= 43566) ||
          (cp >= 43569 && cp <= 43570) || (cp >= 43573 && cp <= 43574) ||
          cp == 43587 || cp == 43596 || cp == 43644 || cp == 43696 ||
          (cp >= 43698 && cp <= 43700) || (cp >= 43703 && cp <= 43704) ||
          (cp >= 43710 && cp <= 43711) || cp == 43713 ||
          (cp >= 43756 && cp <= 43757) || cp == 43766 || cp == 44005 ||
          cp == 44008 || cp == 44013 || cp == 64350 ||
          (cp >= 65024 && cp <= 65039) || (cp >= 65056 && cp <= 65071) ||
          cp == 65279 || (cp >= 917760 && cp <= 917999))
        continue
      if ((cp >= 4352 && cp <= 4447) || (cp >= 9001 && cp <= 9002) ||
          (cp >= 11904 && cp <= 12350) || (cp >= 12353 && cp <= 13311) ||
          (cp >= 13312 && cp <= 19903) || (cp >= 19968 && cp <= 40959) ||
          (cp >= 40960 && cp <= 42191) || (cp >= 43360 && cp <= 43391) ||
          (cp >= 44032 && cp <= 55203) || (cp >= 63744 && cp <= 64255) ||
          (cp >= 65040 && cp <= 65049) || (cp >= 65072 && cp <= 65103) ||
          (cp >= 65280 && cp <= 65376) || (cp >= 65504 && cp <= 65510) ||
          (cp >= 94176 && cp <= 94180) || (cp >= 94208 && cp <= 101589) ||
          (cp >= 110592 && cp <= 111355) ||
          (cp >= 126976 && cp <= 127487) || (cp >= 127488 && cp <= 127743) ||
          (cp >= 127744 && cp <= 128591) || (cp >= 128640 && cp <= 128767) ||
          (cp >= 129280 && cp <= 129535) || (cp >= 129648 && cp <= 129791) ||
          (cp >= 131072 && cp <= 196605) || (cp >= 196608 && cp <= 262141) ||
          (cp >= 8986 && cp <= 8987) || (cp >= 9208 && cp <= 9210) ||
          cp == 9200 || cp == 9203 || (cp >= 9725 && cp <= 9726) ||
          (cp >= 9748 && cp <= 9749) || (cp >= 9800 && cp <= 9811) ||
          cp == 9855 || cp == 9875 || cp == 9889 ||
          (cp >= 9898 && cp <= 9899) || (cp >= 9917 && cp <= 9918) ||
          (cp >= 9924 && cp <= 9925) || cp == 9934 || cp == 9940 ||
          cp == 9962 || (cp >= 9970 && cp <= 9971) || cp == 9973 ||
          cp == 9978 || cp == 9981 || cp == 9989 ||
          (cp >= 9994 && cp <= 9995) || cp == 10024 || cp == 10060 ||
          cp == 10062 || (cp >= 10067 && cp <= 10069) || cp == 10071 ||
          (cp >= 10133 && cp <= 10135) || cp == 10160 || cp == 10175 ||
          (cp >= 11035 && cp <= 11036) || cp == 11088 || cp == 11093)
        w += 2
      else
        w += 1
    }
    return w
  }
  function hit(n, cell) {
    if (n < cur) { before++; return }
    if (n > cur) return
    if (cell < col) { before++; return }
    if (cell == col) res = before + 1
  }
  {
    n = NR - 1
    if (n > cur) exit
    line = ci ? tolower($0) : $0
    if (!re) {
      rest = line
      cells = 0
      while (plen > 0) {
        p = index(rest, lpat)
        if (p == 0) break
        pre = substr(rest, 1, p - 1)
        w = cw(pre)
        hit(n, cells + w)
        if (res != "") exit
        cells += w + cw(substr(rest, p, plen))
        rest = substr(rest, p + plen)
      }
    } else {
      rest = line
      cells = 0
      base = 0
      while (length(rest) > 0) {
        if (bol && base > 0) break
        if (!match(rest, rpat)) break
        if (RLENGTH == 0) {
          b = ORD[substr(rest, 1, 1)]
          adv = 1
          if (b >= 240) adv = 4
          else if (b >= 224) adv = 3
          else if (b >= 192) adv = 2
          cells += cw(substr(rest, 1, adv))
          rest = substr(rest, adv + 1)
          base += adv
          continue
        }
        pre = substr(rest, 1, RSTART - 1)
        w = cw(pre)
        hit(n, cells + w)
        if (res != "") exit
        adv = RSTART + RLENGTH - 1
        cells += w + cw(substr(rest, RSTART, RLENGTH))
        rest = substr(rest, adv + 1)
        base += adv
      }
    }
  }
  END { print res }
  ' 2>/dev/null || true)"

if [[ -n "$index" ]]; then
  # Number matches from the end the search starts at: forward searches count
  # from the top of the buffer, backward searches from the bottom. The awk
  # scan above is always top-down, so reverse it for backward searches when
  # the total is complete. A partial count has no known bottom end; keep the
  # top-down number there (the native n/N path is disabled for partial counts
  # anyway, and the next complete count fixes the index).
  if [[ "$dir" == "backward" && "${partial:-0}" != "1" && "$total" =~ ^[0-9]+$ ]]; then
    index=$(( total - index + 1 ))
  fi
  if [[ "${partial:-0}" != "1" && "$index" -gt "$total" ]]; then
    index="$total"
  fi
  cmh_set "$index" "$line,$cx"
else
  cmh_clear
fi
