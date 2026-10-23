#!/usr/bin/env bash
# search.sh <direction> <pane> <pattern>
direction="${1:-}"
pane="${2:-}"
pattern="${3:-}"
[ -z "$pane" ] && exit 0
if [[ -z "$pattern" ]]; then
  # Prompt searches store the response in a pane option so command-prompt's
  # template parser cannot eat regex backslashes or shell metacharacters.
  pattern="$(tmux show-option -pv -t "$pane" @cmh_search_input 2>/dev/null || true)"
  tmux set-option -pu -t "$pane" @cmh_search_input >/dev/null 2>&1
fi
[ -z "$pattern" ] && exit 0
if [[ "$direction" == "backward" ]]; then
  tmux set-option -p -t "$pane" @cmh_search_dir backward \; \
       set-option -p -t "$pane" @cmh_search_pattern "$pattern" \; \
       set-option -p -t "$pane" @cmh_search_regex 1 \; \
       set-option -p -t "$pane" @cmh_search_index '' \; \
       set-option -p -t "$pane" @cmh_search_pos '' >/dev/null 2>&1
  tmux send-keys -t "$pane" -X search-backward -- "$pattern"
else
  tmux set-option -p -t "$pane" @cmh_search_dir forward \; \
       set-option -p -t "$pane" @cmh_search_pattern "$pattern" \; \
       set-option -p -t "$pane" @cmh_search_regex 1 \; \
       set-option -p -t "$pane" @cmh_search_index '' \; \
       set-option -p -t "$pane" @cmh_search_pos '' >/dev/null 2>&1
  tmux send-keys -t "$pane" -X search-forward -- "$pattern"
fi
# Record which result the cursor landed on (own index if tmux only knows the
# total).
"${0%/*}/search-index.sh" "$pane"
