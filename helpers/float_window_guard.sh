#!/bin/sh
set -u

TOP_INSET=30
YABAI_BIN=yabai
JQ_BIN=jq

clamp_frame() {
  if [ "$#" -ne 16 ]; then
    printf '%s\n' 'usage: --clamp x y width height display_x display_y display_width display_height has_ax floating native_fullscreen visible minimized hidden can_move can_resize' >&2
    return 2
  fi

  x=$1
  y=$2
  width=$3
  height=$4
  display_y=$6
  display_height=$8
  has_ax=$9
  shift 9
  is_floating=$1
  is_native_fullscreen=$2
  is_visible=$3
  is_minimized=$4
  is_hidden=$5
  can_move=$6
  can_resize=$7

  if [ "$has_ax" -ne 1 ] ||
    [ "$is_floating" -ne 1 ] ||
    [ "$is_native_fullscreen" -ne 0 ] ||
    [ "$is_visible" -ne 1 ] ||
    [ "$is_minimized" -ne 0 ] ||
    [ "$is_hidden" -ne 0 ] ||
    [ "$can_move" -ne 1 ]; then
    printf '%s\n' 'skip'
    return 0
  fi

  awk \
    -v x="$x" \
    -v y="$y" \
    -v width="$width" \
    -v height="$height" \
    -v display_y="$display_y" \
    -v display_height="$display_height" \
    -v inset="$TOP_INSET" \
    -v can_resize="$can_resize" \
    'BEGIN {
      safe_top = display_y + inset
      display_bottom = display_y + display_height
      new_y = (y < safe_top) ? safe_top : y
      new_height = height

      if (can_resize == 1 && new_y + new_height > display_bottom) {
        new_height = display_bottom - new_y
        if (new_height < 1) new_height = 1
      }

      move_needed = (new_y != y) ? 1 : 0
      resize_needed = (new_height != height) ? 1 : 0
      printf "%g %g %g %g %d %d\n", \
        x, new_y, width, new_height, move_needed, resize_needed
    }'
}

guard_window() {
  window_id=$1
  window_json=$("$YABAI_BIN" -m query --windows --window "$window_id" 2>/dev/null) || return 0
  display_index=$(printf '%s\n' "$window_json" | "$JQ_BIN" -r '.display // empty' 2>/dev/null) || return 0
  [ -n "$display_index" ] || return 0

  display_json=$("$YABAI_BIN" -m query --displays --display "$display_index" 2>/dev/null) || return 0

  values=$(printf '%s\n%s\n' "$window_json" "$display_json" |
    "$JQ_BIN" -s -r '
      . as [$w, $d] |
      [
        $w.frame.x,
        $w.frame.y,
        $w.frame.w,
        $w.frame.h,
        $d.frame.x,
        $d.frame.y,
        $d.frame.w,
        $d.frame.h,
        (if $w["has-ax-reference"] == false then 0 else 1 end),
        (if $w["is-floating"] == true then 1 else 0 end),
        (if $w["is-native-fullscreen"] == true then 1 else 0 end),
        (if $w["is-visible"] == true then 1 else 0 end),
        (if $w["is-minimized"] == true then 1 else 0 end),
        (if $w["is-hidden"] == true then 1 else 0 end),
        (if $w["can-move"] == true then 1 else 0 end),
        (if $w["can-resize"] == true then 1 else 0 end)
      ] | @tsv
    ' 2>/dev/null) || return 0

  # Values are numeric and contain no whitespace.
  # shellcheck disable=SC2086
  set -- $values
  [ "$#" -eq 16 ] || return 0

  result=$("$0" --clamp "$@") || return 0
  [ "$result" = 'skip' ] && return 0

  # shellcheck disable=SC2086
  set -- $result
  [ "$#" -eq 6 ] || return 0

  new_x=$1
  new_y=$2
  new_width=$3
  new_height=$4
  move_needed=$5
  resize_needed=$6

  if [ "$move_needed" -eq 1 ]; then
    "$YABAI_BIN" -m window "$window_id" --move "abs:$new_x:$new_y" >/dev/null 2>&1 || return 0
  fi

  if [ "$resize_needed" -eq 1 ]; then
    "$YABAI_BIN" -m window "$window_id" --resize "abs:$new_width:$new_height" >/dev/null 2>&1 || return 0
  fi
}

guard_all() {
  ids=$("$YABAI_BIN" -m query --windows 2>/dev/null | "$JQ_BIN" -r '.[].id' 2>/dev/null) || return 0
  for window_id in $ids; do
    guard_window "$window_id"
  done
}

if [ "$#" -lt 1 ]; then
  printf '%s\n' 'usage: float_window_guard.sh <window-id|all>' >&2
  exit 2
fi

case "$1" in
  --clamp)
    shift
    clamp_frame "$@"
    ;;
  all)
    guard_all
    ;;
  *)
    guard_window "$1"
    ;;
esac

