#!/bin/sh
set -eu

[ "${1:-}" = '-m' ] || exit 2
shift

if [ "$1" = 'query' ] && [ "$2" = '--windows' ]; then
  printf '%s\n' '{"display":1,"space":3,"frame":{"x":0,"y":0,"w":100,"h":100},"has-ax-reference":true,"is-floating":false,"is-native-fullscreen":false,"is-visible":true,"is-minimized":false,"is-hidden":false,"can-move":true,"can-resize":true}'
  exit 0
fi

if [ "$1" = 'query' ] && [ "$2" = '--displays' ]; then
  printf '%s\n' '{"frame":{"x":0,"y":0,"w":1440,"h":900}}'
  exit 0
fi

if [ "$1" = 'query' ] && [ "$2" = '--spaces' ]; then
  printf '%s\n' '{"type":"float"}'
  exit 0
fi

if [ "$1" = 'window' ]; then
  printf '%s\n' "$*" >> "$FLOAT_WINDOW_GUARD_TEST_LOG"
  exit 0
fi

exit 2
