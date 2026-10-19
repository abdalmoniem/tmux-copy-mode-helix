#!/usr/bin/env bash
pane="${1:-}"
[ -z "$pane" ] && exit 0
tmux copy-mode -t "$pane"
tmux set-option -p -t "$pane" @cmh_mode normal \; \
     set-option -p -t "$pane" @cmh_keys '' \; \
     set-option -p -t "$pane" @cmh_pending '' \; \
     set-option -p -t "$pane" @cmh_x_sel '' \; \
     set-option -p -t "$pane" @cmh_search_index '' \; \
     set-option -p -t "$pane" @cmh_search_pos '' \; \
     set-option -p -t "$pane" @cmh_search_pattern '' \; \
     set-option -p -t "$pane" @cmh_search_regex '' \; \
     set-option -p -t "$pane" @cmh_search_dir '' >/dev/null 2>&1
