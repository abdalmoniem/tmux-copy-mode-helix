#!/usr/bin/env bash
# unimp-next.sh <pane> <key>   (Helix ']')
pane="${1:-}"
key="${2:-}"
[ -z "$pane" ] && exit 0
source "${0%/*}/common.sh"
case "$key" in
  p) "${0%/*}/move.sh" next-paragraph "$pane" ;;
  *) cmh_alert "$pane" "unsupported ']' key '$key'" ;;
esac
